BEGIN;

CREATE TABLE public.reviewed_ai_bread_requests (
    request_id uuid PRIMARY KEY,
    actor_user_id uuid NOT NULL REFERENCES public.user_profiles(user_id),
    payload_hash text NOT NULL,
    result jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.reviewed_ai_bread_requests ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.create_reviewed_ai_bread_with_audit(
    p_actor_user_id uuid, p_request_id uuid, p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    existing public.reviewed_ai_bread_requests%ROWTYPE;
    category_data jsonb;
    item jsonb;
    new_data jsonb;
    category_id uuid;
    ingredient_id uuid;
    ingredient_name text;
    used_ingredients uuid[] := ARRAY[]::uuid[];
    new_count integer := 0;
    result_value jsonb;
    payload_digest text;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id AND role = 'SYSTEM_ADMINISTRATOR'
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Active administrator required.';
    END IF;
    IF p_request_id IS NULL OR p_payload IS NULL OR
       pg_catalog.jsonb_typeof(p_payload) <> 'object' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid reviewed draft.';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('smart-bakery-inventory-master', 0));
    payload_digest := pg_catalog.md5(p_payload::text);
    SELECT * INTO existing FROM public.reviewed_ai_bread_requests
    WHERE request_id = p_request_id FOR UPDATE;
    IF FOUND THEN
        IF existing.actor_user_id <> p_actor_user_id OR
           existing.payload_hash <> payload_digest THEN
            RAISE EXCEPTION USING ERRCODE = 'P0001',
                MESSAGE = 'This request ID was already used for another draft.';
        END IF;
        RETURN existing.result;
    END IF;
    category_data := p_payload->'category';
    IF pg_catalog.jsonb_typeof(category_data) <> 'object' OR
       pg_catalog.jsonb_typeof(category_data->'name') <> 'string' OR
       pg_catalog.length(pg_catalog.btrim(category_data->>'name')) NOT BETWEEN 1 AND 120 OR
       (category_data->'description' IS NOT NULL AND
        pg_catalog.jsonb_typeof(category_data->'description') NOT IN ('string', 'null')) OR
       pg_catalog.jsonb_typeof(category_data->'displayOrder') <> 'number' OR
       pg_catalog.jsonb_typeof(category_data->'shelfLifeHours') <> 'number' OR
       pg_catalog.jsonb_typeof(category_data->'sellingPrice') <> 'number' OR
       (category_data->>'displayOrder')::integer < 0 OR
       (category_data->>'shelfLifeHours')::integer <= 0 OR
       (category_data->>'sellingPrice')::numeric < 0 OR
       pg_catalog.jsonb_typeof(p_payload->'recipe') <> 'array' OR
       pg_catalog.jsonb_array_length(p_payload->'recipe') NOT BETWEEN 1 AND 15 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid category or recipe fields.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.bread_categories
               WHERE pg_catalog.lower(pg_catalog.btrim(name)) =
                 pg_catalog.lower(pg_catalog.btrim(category_data->>'name'))) THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Bread category name already exists.';
    END IF;
    INSERT INTO public.bread_categories
        (name, description, display_order, shelf_life_hours, selling_price, is_active)
    VALUES (pg_catalog.btrim(category_data->>'name'),
        nullif(pg_catalog.btrim(category_data->>'description'), ''),
        (category_data->>'displayOrder')::integer,
        (category_data->>'shelfLifeHours')::integer,
        (category_data->>'sellingPrice')::numeric, false)
    RETURNING id INTO category_id;

    FOR item IN SELECT value FROM pg_catalog.jsonb_array_elements(p_payload->'recipe') AS entry(value)
    LOOP
        IF pg_catalog.jsonb_typeof(item) <> 'object' OR
           pg_catalog.jsonb_typeof(item->'gramsPerUnit') <> 'number' OR
           (item->>'gramsPerUnit')::numeric <= 0 OR
           (item->>'gramsPerUnit')::numeric > 2000 OR
           (item->>'gramsPerUnit')::numeric <> pg_catalog.round(
               (item->>'gramsPerUnit')::numeric, 3) THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Invalid recipe grams.';
        END IF;
        IF pg_catalog.jsonb_typeof(item->'ingredientId') = 'string' AND
           pg_catalog.jsonb_typeof(item->'newIngredient') = 'null' THEN
            ingredient_id := (item->>'ingredientId')::uuid;
            PERFORM 1 FROM public.ingredients WHERE id = ingredient_id AND is_active FOR SHARE;
            IF NOT FOUND THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'Existing recipe ingredient is unavailable or inactive.';
            END IF;
        ELSIF pg_catalog.jsonb_typeof(item->'ingredientId') = 'null' AND
              pg_catalog.jsonb_typeof(item->'newIngredient') = 'object' THEN
            new_data := item->'newIngredient';
            ingredient_name := pg_catalog.btrim(new_data->>'name');
            IF pg_catalog.length(ingredient_name) NOT BETWEEN 1 AND 120 OR
               new_data->>'unit' NOT IN ('G', 'KG') OR
               pg_catalog.jsonb_typeof(new_data->'referenceUnitCost') <> 'number' OR
               pg_catalog.jsonb_typeof(new_data->'reorderThresholdGrams') <> 'number' OR
               (new_data->>'referenceUnitCost')::numeric < 0 OR
               (new_data->>'reorderThresholdGrams')::numeric < 0 OR
               (new_data->>'reorderThresholdGrams')::numeric <> pg_catalog.round(
                   (new_data->>'reorderThresholdGrams')::numeric, 3) OR
               EXISTS (SELECT 1 FROM public.ingredients WHERE
                 pg_catalog.lower(pg_catalog.btrim(name)) = pg_catalog.lower(ingredient_name)) THEN
                RAISE EXCEPTION USING ERRCODE = 'P0001',
                    MESSAGE = 'New ingredient fields are invalid or its name already exists.';
            END IF;
            INSERT INTO public.ingredients (name, unit, unit_cost,
                reorder_threshold, is_active)
            VALUES (ingredient_name, new_data->>'unit',
                (new_data->>'referenceUnitCost')::numeric,
                (new_data->>'reorderThresholdGrams')::numeric, true)
            RETURNING id INTO ingredient_id;
            INSERT INTO public.inventory (ingredient_id, quantity_grams, updated_by)
            VALUES (ingredient_id, 0, p_actor_user_id);
            new_count := new_count + 1;
        ELSE
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Choose one ingredient source.';
        END IF;
        IF ingredient_id = ANY(used_ingredients) THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Duplicate recipe ingredient.';
        END IF;
        used_ingredients := pg_catalog.array_append(used_ingredients, ingredient_id);
        INSERT INTO public.recipes (bread_category_id, ingredient_id, grams_per_unit)
        VALUES (category_id, ingredient_id, (item->>'gramsPerUnit')::numeric);
    END LOOP;
    UPDATE public.bread_categories SET is_active = true WHERE id = category_id;
    result_value := pg_catalog.jsonb_build_object('categoryId', category_id,
        'createdIngredientCount', new_count);
    INSERT INTO public.reviewed_ai_bread_requests
        (request_id, actor_user_id, payload_hash, result)
    VALUES (p_request_id, p_actor_user_id, payload_digest, result_value);
    INSERT INTO public.system_logs
        (actor_user_id, event_type, entity_type, entity_id, outcome, severity, payload)
    VALUES (p_actor_user_id, 'CREATE_REVIEWED_AI_BREAD', 'bread_categories',
        category_id, 'SUCCESS', 'INFO',
        pg_catalog.jsonb_build_object('request_id', p_request_id));
    RETURN result_value;
END;
$$;

REVOKE ALL ON public.reviewed_ai_bread_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_reviewed_ai_bread_with_audit(uuid, uuid, jsonb)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_reviewed_ai_bread_with_audit(uuid, uuid, jsonb)
    TO service_role;
COMMIT;
