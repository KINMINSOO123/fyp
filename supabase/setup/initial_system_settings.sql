INSERT INTO public.system_settings (
    setting_key,
    setting_value,
    data_type,
    description,
    updated_by
)
SELECT
    'prediction.low_confidence_threshold',
    '75'::jsonb,
    'NUMERIC',
    'Model confidence below this percentage is labelled Low Confidence.',
    user_id
FROM public.user_profiles
WHERE user_id = 'PASTE_ADMIN_USER_ID_HERE'::uuid
  AND role = 'SYSTEM_ADMINISTRATOR'
  AND account_status = 'ACTIVE'
RETURNING *;