-- Reuse the physical route driver so ordinary outings receive the same real
-- App update/save/reload, parking, dismount and registered-door checks.
return {run=require('src.commute.tests.apartment_journey_test').runOuting}
