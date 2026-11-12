-- Example configuration for the manual next-day prediction workflow.
-- Replace the administrator UUID before running this file. Every active
-- category missing a cold-start base gets a provisional 10-unit demo base.
-- Existing base quantities and other configured factors are preserved.
-- Initial Kuala Lumpur demo assumptions, not scientifically validated effects.
-- ON CONFLICT below changes base quantities only. It NEVER replaces existing
-- weekday/weather/holiday/monsoon factors. To apply demo factors to an
-- existing bakery, use Settings > Use demo defaults > Save, or run the separate
-- apply_demo_prediction_factors.sql script intentionally.
-- Missing weather/calendar data use explicitly labelled neutral fallbacks.

WITH demo_bases AS (
    SELECT coalesce(jsonb_object_agg(id::text, to_jsonb(10)), '{}'::jsonb)
        AS base_quantities
    FROM public.bread_categories
    WHERE is_active
)
INSERT INTO public.system_settings (
    setting_key, setting_value, data_type, description, updated_by
)
SELECT
    'prediction.context_rules',
    jsonb_set('{
      "baseQuantities": {},
      "weekdayFactors": {
        "SUNDAY": 1.10, "MONDAY": 1, "TUESDAY": 1, "WEDNESDAY": 1,
        "THURSDAY": 1, "FRIDAY": 1, "SATURDAY": 1.10
      },
      "monsoonMonths": [],
      "monsoonFactor": 1,
      "otherSeasonFactor": 1,
      "weatherFactors": {
        "CLEAR": 1, "CLOUDY": 1, "RAIN": 0.95, "STORM": 0.90, "OTHER": 1
      },
      "weatherFallbackFactor": 1,
      "holidayFactor": 1.05,
      "nonHolidayFactor": 1,
      "calendarVerifiedThrough": null,
      "allowCalendarFallback": true
    }'::jsonb, '{baseQuantities}', demo_bases.base_quantities, true),
    'JSON',
    'Configured prediction factors and explicitly labelled context fallbacks.',
    user_id
FROM public.user_profiles CROSS JOIN demo_bases
WHERE user_id = 'PASTE_ADMIN_USER_ID_HERE'::uuid
  AND role = 'SYSTEM_ADMINISTRATOR'
  AND account_status = 'ACTIVE'
ON CONFLICT (setting_key) DO UPDATE
SET setting_value = jsonb_set(
        public.system_settings.setting_value,
        '{baseQuantities}',
        (EXCLUDED.setting_value -> 'baseQuantities') ||
        coalesce(public.system_settings.setting_value -> 'baseQuantities', '{}'::jsonb),
        true
    ),
    updated_by = EXCLUDED.updated_by;
