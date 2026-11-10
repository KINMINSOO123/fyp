BEGIN;

-- Each RPC invocation is one PostgreSQL transaction. Node supplies the actor
-- derived from the verified JWT; the functions recheck the stored active role.
CREATE FUNCTION public.allocate_leftover_with_audit(
    p_actor_user_id uuid,
    p_action text,
    p_daily_result_id uuid,
    p_quantity integer,
    p_charity_partner_id uuid,
    p_disposal_reason text,
    p_notes text,
    p_confirm boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    result_row public.daily_results%ROWTYPE;
    bakery_day date;
    donated_value integer;
    wasted_value integer;
    allocation_id uuid;
    normalized_reason text := NULLIF(pg_catalog.btrim(p_disposal_reason), '');
    normalized_notes text := NULLIF(pg_catalog.btrim(p_notes), '');
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id AND role = 'BAKERY_MANAGER'
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active Bakery Manager is required.';
    END IF;
    IF p_confirm IS DISTINCT FROM true OR p_action IS NULL OR
       p_action NOT IN ('DONATE', 'WASTE') OR
       p_daily_result_id IS NULL OR p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'A confirmed positive leftover allocation is required.';
    END IF;
    IF (p_action = 'DONATE' AND
          (p_charity_partner_id IS NULL OR normalized_reason IS NOT NULL)) OR
       (p_action = 'WASTE' AND
          (p_charity_partner_id IS NOT NULL OR normalized_reason IS NULL)) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Invalid donation partner or waste disposal reason.';
    END IF;

    SELECT * INTO result_row FROM public.daily_results
    WHERE id = p_daily_result_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002',
            MESSAGE = 'The completed daily result was not found.';
    END IF;
    SELECT (now() AT TIME ZONE settings.timezone)::date INTO bakery_day
    FROM public.bakery_settings AS settings
    WHERE settings.singleton_guard = true;
    IF NOT FOUND OR bakery_day < result_row.result_date THEN
        RAISE EXCEPTION USING ERRCODE = 'P1004',
            MESSAGE = 'The allocation date cannot precede the result date.';
    END IF;
    SELECT COALESCE(sum(quantity), 0) INTO donated_value
    FROM public.donations WHERE daily_result_id = p_daily_result_id;
    SELECT COALESCE(sum(quantity), 0) INTO wasted_value
    FROM public.waste_records WHERE daily_result_id = p_daily_result_id;
    IF result_row.leftover <> donated_value + wasted_value +
       result_row.remaining_unallocated_leftover THEN
        RAISE EXCEPTION USING ERRCODE = 'P1004',
            MESSAGE = 'The stored leftover balance does not reconcile.';
    END IF;
    IF p_quantity > result_row.remaining_unallocated_leftover THEN
        RAISE EXCEPTION USING ERRCODE = 'P1003',
            MESSAGE = 'The requested quantity exceeds unallocated leftovers.';
    END IF;

    IF p_action = 'DONATE' THEN
        PERFORM 1 FROM public.charity_partners
        WHERE id = p_charity_partner_id AND is_active = true FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P1002',
                MESSAGE = 'An active charity partner is required.';
        END IF;
        INSERT INTO public.donations (
            daily_result_id, charity_partner_id, donation_date, quantity,
            status, confirmed_by, notes
        ) VALUES (
            p_daily_result_id, p_charity_partner_id, bakery_day, p_quantity,
            'PENDING', p_actor_user_id, normalized_notes
        ) RETURNING id INTO allocation_id;
    ELSE
        INSERT INTO public.waste_records (
            daily_result_id, waste_date, quantity, disposal_reason, confirmed_by
        ) VALUES (
            p_daily_result_id, bakery_day, p_quantity,
            normalized_reason, p_actor_user_id
        ) RETURNING id INTO allocation_id;
    END IF;
    UPDATE public.daily_results SET
        remaining_unallocated_leftover = remaining_unallocated_leftover - p_quantity
    WHERE id = p_daily_result_id;
    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, CASE WHEN p_action = 'DONATE'
            THEN 'DONATION_ALLOCATED' ELSE 'WASTE_RECORDED' END,
        CASE WHEN p_action = 'DONATE' THEN 'donations' ELSE 'waste_records' END,
        allocation_id, 'SUCCESS', 'INFO',
        pg_catalog.jsonb_build_object(
            'daily_result_id', p_daily_result_id,
            'quantity', p_quantity,
            'remaining_unallocated',
                result_row.remaining_unallocated_leftover - p_quantity)
    );
    RETURN pg_catalog.jsonb_build_object(
        'allocationId', allocation_id, 'type', p_action,
        'date', bakery_day, 'quantity', p_quantity,
        'remainingUnallocated',
            result_row.remaining_unallocated_leftover - p_quantity,
        'status', CASE WHEN p_action = 'DONATE' THEN 'PENDING' ELSE NULL END);
END;
$$;

CREATE FUNCTION public.advance_donation_status_with_audit(
    p_actor_user_id uuid,
    p_donation_id uuid,
    p_status text,
    p_confirm boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    donation_row public.donations%ROWTYPE;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id AND role = 'BAKERY_MANAGER'
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active Bakery Manager is required.';
    END IF;
    IF p_confirm IS DISTINCT FROM true OR p_donation_id IS NULL OR
       p_status IS NULL OR p_status NOT IN ('COLLECTED', 'COMPLETED') THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'A confirmed supported donation status is required.';
    END IF;
    SELECT * INTO donation_row FROM public.donations
    WHERE id = p_donation_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002',
            MESSAGE = 'Donation not found.';
    END IF;
    IF NOT ((donation_row.status = 'PENDING' AND p_status = 'COLLECTED') OR
            (donation_row.status = 'COLLECTED' AND p_status = 'COMPLETED')) THEN
        RAISE EXCEPTION USING ERRCODE = 'P1003',
            MESSAGE = 'Donation status must progress from pending to collected to completed.';
    END IF;
    UPDATE public.donations SET status = p_status
    WHERE id = p_donation_id;
    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, 'DONATION_STATUS_CHANGED', 'donations',
        p_donation_id, 'SUCCESS', 'INFO',
        pg_catalog.jsonb_build_object('previous_status', donation_row.status,
            'new_status', p_status, 'daily_result_id', donation_row.daily_result_id)
    );
    RETURN pg_catalog.jsonb_build_object(
        'donationId', p_donation_id, 'status', p_status,
        'dailyResultId', donation_row.daily_result_id);
END;
$$;

CREATE FUNCTION public.save_charity_partner_with_audit(
    p_actor_user_id uuid,
    p_partner_id uuid,
    p_name text,
    p_contact_info text,
    p_is_active boolean
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
    changed_id uuid;
    event_name text;
BEGIN
    PERFORM 1 FROM public.user_profiles
    WHERE user_id = p_actor_user_id AND role = 'SYSTEM_ADMINISTRATOR'
      AND account_status = 'ACTIVE' FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '42501',
            MESSAGE = 'An active System Administrator is required.';
    END IF;
    IF p_name IS NULL OR pg_catalog.btrim(p_name) = '' OR
       pg_catalog.length(pg_catalog.btrim(p_name)) > 120 OR
       p_is_active IS NULL OR
       (p_contact_info IS NOT NULL AND
        pg_catalog.length(pg_catalog.btrim(p_contact_info)) > 500) THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Invalid charity partner details.';
    END IF;
    IF p_partner_id IS NULL THEN
        INSERT INTO public.charity_partners (name, contact_info, is_active)
        VALUES (pg_catalog.btrim(p_name),
                NULLIF(pg_catalog.btrim(p_contact_info), ''), p_is_active)
        RETURNING id INTO changed_id;
        event_name := 'CHARITY_PARTNER_CREATED';
    ELSE
        UPDATE public.charity_partners SET
            name = pg_catalog.btrim(p_name),
            contact_info = NULLIF(pg_catalog.btrim(p_contact_info), ''),
            is_active = p_is_active
        WHERE id = p_partner_id RETURNING id INTO changed_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'P0002',
                MESSAGE = 'Charity partner not found.';
        END IF;
        event_name := 'CHARITY_PARTNER_UPDATED';
    END IF;
    INSERT INTO public.system_logs (
        actor_user_id, event_type, entity_type, entity_id,
        outcome, severity, payload
    ) VALUES (
        p_actor_user_id, event_name, 'charity_partners', changed_id,
        'SUCCESS', 'INFO',
        pg_catalog.jsonb_build_object('is_active', p_is_active)
    );
    RETURN changed_id;
END;
$$;

REVOKE ALL ON FUNCTION public.allocate_leftover_with_audit(
    uuid, text, uuid, integer, uuid, text, text, boolean)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.advance_donation_status_with_audit(
    uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_charity_partner_with_audit(
    uuid, uuid, text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_leftover_with_audit(
    uuid, text, uuid, integer, uuid, text, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.advance_donation_status_with_audit(
    uuid, uuid, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_charity_partner_with_audit(
    uuid, uuid, text, text, boolean) TO service_role;

-- Pre-aggregate each allocation table before joining to the result. This
-- prevents donation x waste fan-out and keeps reporting quantities correct.
CREATE VIEW public.leftover_allocation_summary
WITH (security_invoker = true)
AS
SELECT result.id AS daily_result_id,
       result.result_date, result.bread_category_id,
       category.name AS bread_category_name,
       result.produced, result.units_sold, result.leftover,
       COALESCE(donation.total, 0)::integer AS donated,
       COALESCE(waste.total, 0)::integer AS wasted,
       result.remaining_unallocated_leftover
FROM public.daily_results AS result
JOIN public.bread_categories AS category
  ON category.id = result.bread_category_id
LEFT JOIN (
    SELECT daily_result_id, sum(quantity) AS total
    FROM public.donations GROUP BY daily_result_id
) AS donation ON donation.daily_result_id = result.id
LEFT JOIN (
    SELECT daily_result_id, sum(quantity) AS total
    FROM public.waste_records GROUP BY daily_result_id
) AS waste ON waste.daily_result_id = result.id;
REVOKE ALL ON public.leftover_allocation_summary
    FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.leftover_allocation_summary TO service_role;

COMMIT;
