-- Example configuration for the manual next-day prediction workflow.
-- Replace the administrator UUID and add baseQuantities entries for categories
-- without any validated sales history before running this file.
-- Neutral factors are deliberate starting values, not measured demand effects.
-- Missing weather/calendar data use explicitly labelled neutral fallbacks.

INSERT INTO public.system_settings (
    setting_key, setting_value, data_type, description, updated_by
)
SELECT
    'prediction.context_rules',
    '{
      "baseQuantities": {},
      "weekdayFactors": {
        "SUNDAY": 1, "MONDAY": 1, "TUESDAY": 1, "WEDNESDAY": 1,
        "THURSDAY": 1, "FRIDAY": 1, "SATURDAY": 1
      },
      "monsoonMonths": [],
      "monsoonFactor": 1,
      "otherSeasonFactor": 1,
      "weatherFactors": {
        "CLEAR": 1, "CLOUDY": 1, "RAIN": 1, "STORM": 1, "OTHER": 1
      },
      "weatherFallbackFactor": 1,
      "holidayFactor": 1,
      "nonHolidayFactor": 1,
      "calendarVerifiedThrough": null,
      "allowCalendarFallback": true
    }'::jsonb,
    'JSON',
    'Configured prediction factors and explicitly labelled context fallbacks.',
    user_id
FROM public.user_profiles
WHERE user_id = 'PASTE_ADMIN_USER_ID_HERE'::uuid
  AND role = 'SYSTEM_ADMINISTRATOR'
  AND account_status = 'ACTIVE'
ON CONFLICT (setting_key) DO UPDATE
SET setting_value = EXCLUDED.setting_value,
    data_type = EXCLUDED.data_type,
    description = EXCLUDED.description,
    updated_by = EXCLUDED.updated_by;
