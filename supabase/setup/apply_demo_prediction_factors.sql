-- Optional, explicit update for an EXISTING bakery's prediction context.
-- Replace the UUID with the intended ACTIVE SYSTEM_ADMINISTRATOR user ID.
-- To find it, run separately:
-- SELECT user_id FROM public.user_profiles
-- WHERE role = 'SYSTEM_ADMINISTRATOR' AND account_status = 'ACTIVE';
-- Run this whole script once in Supabase SQL Editor only if you want the
-- Kuala Lumpur demo assumptions. It records a SYSTEM_SETTING_UPDATED audit.
-- It preserves category bases, weather/calendar fallback settings and all
-- other existing keys. It does not change saved predictions or train models.

BEGIN;

DO $$
DECLARE
    administrator_id uuid := 'PASTE_ADMIN_USER_ID_HERE'::uuid;
    current_rules jsonb;
    demo_rules jsonb;
BEGIN
    SELECT setting_value INTO current_rules
    FROM public.system_settings
    WHERE setting_key = 'prediction.context_rules'
    FOR UPDATE;

    IF current_rules IS NULL THEN
        RAISE EXCEPTION 'prediction.context_rules is missing; run initial setup first.';
    END IF;

    demo_rules := current_rules || '{
      "weekdayFactors": {
        "MONDAY": 1.00, "TUESDAY": 1.00, "WEDNESDAY": 1.00,
        "THURSDAY": 1.00, "FRIDAY": 1.00,
        "SATURDAY": 1.10, "SUNDAY": 1.10
      },
      "monsoonMonths": [],
      "monsoonFactor": 1.00,
      "otherSeasonFactor": 1.00,
      "weatherFactors": {
        "CLEAR": 1.00, "CLOUDY": 1.00, "RAIN": 0.95,
        "STORM": 0.90, "OTHER": 1.00
      },
      "holidayFactor": 1.05,
      "nonHolidayFactor": 1.00
    }'::jsonb;

    PERFORM public.update_admin_system_setting_with_audit(
        administrator_id, 'prediction.context_rules', demo_rules
    );
END;
$$;

COMMIT;

-- Read-only verification after the update:
SELECT setting_value -> 'weekdayFactors' AS weekday_factors,
       setting_value -> 'weatherFactors' AS weather_factors,
       setting_value -> 'holidayFactor' AS holiday_factor,
       setting_value -> 'nonHolidayFactor' AS non_holiday_factor,
       setting_value -> 'monsoonMonths' AS monsoon_months,
       setting_value -> 'monsoonFactor' AS monsoon_factor,
       setting_value -> 'otherSeasonFactor' AS other_season_factor
FROM public.system_settings
WHERE setting_key = 'prediction.context_rules';
