#include "eco_engine.h"
#include <math.h>
#include <stddef.h>

static float clampf(float v, float lo, float hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static float celsius_to_fahrenheit(float c) {
    return c * 9.0f / 5.0f + 32.0f;
}

static float fahrenheit_to_celsius(float f) {
    return (f - 32.0f) * 5.0f / 9.0f;
}

static float heat_index_fahrenheit(float t_f, float rh) {
    rh = clampf(rh, 0.0f, 100.0f);
    t_f = clampf(t_f, -50.0f, 130.0f);

    if (t_f < 80.0f) {
        float hi = 0.5f * (t_f + 61.0f + ((t_f - 68.0f) * 1.2f) + (rh * 0.094f));
        return hi;
    }

    float hi = -42.379f
        + 2.04901523f * t_f
        + 10.14333127f * rh
        - 0.22475541f * t_f * rh
        - 6.83783e-3f * t_f * t_f
        - 5.481717e-2f * rh * rh
        + 1.22874e-3f * t_f * t_f * rh
        + 8.5282e-4f * t_f * rh * rh
        - 1.99e-6f * t_f * t_f * rh * rh;

    if (rh < 13.0f && t_f >= 80.0f && t_f <= 112.0f) {
        float adj = ((13.0f - rh) / 4.0f) * sqrtf((17.0f - fabsf(t_f - 95.0f)) / 17.0f);
        hi -= adj;
    } else if (rh > 85.0f && t_f >= 80.0f && t_f <= 87.0f) {
        float adj = ((rh - 85.0f) / 10.0f) * ((87.0f - t_f) / 5.0f);
        hi -= adj;
    }

    return hi;
}

static float heat_index_celsius(float temp_c, float humidity_pct) {
    float tf = celsius_to_fahrenheit(temp_c);
    float hi_f = heat_index_fahrenheit(tf, humidity_pct);
    return fahrenheit_to_celsius(hi_f);
}

float calculate_eco_ventilation_score(
    float outdoorTemp,
    float indoorTemp,
    float humidity
) {
    float out_c = clampf(outdoorTemp, -50.0f, 60.0f);
    float in_c = clampf(indoorTemp, -50.0f, 60.0f);
    float rh = clampf(humidity, 0.0f, 100.0f);

    float hi_in = heat_index_celsius(in_c, rh);
    float hi_out = heat_index_celsius(out_c, rh);

    float delta = hi_in - hi_out;
    if (delta < 0.0f) {
        delta = 0.0f;
    }

    float benefit = delta / 18.0f;
    if (benefit > 1.0f) {
        benefit = 1.0f;
    }

    float temp_delta = fabsf(in_c - out_c);
    float temp_boost = clampf(temp_delta / 15.0f, 0.0f, 1.0f);
    float combined = 0.65f * benefit + 0.35f * temp_boost;

    float rh_factor = 1.0f;
    if (rh > 60.0f) {
        float excess = rh - 60.0f;
        rh_factor = 1.0f - 0.008f * excess;
        if (rh_factor < 0.35f) {
            rh_factor = 0.35f;
        }
    }

    float extreme = 1.0f;
    if (out_c < 5.0f) {
        extreme = 0.25f + 0.75f * clampf((out_c + 10.0f) / 15.0f, 0.0f, 1.0f);
    } else if (out_c > 38.0f) {
        float over = out_c - 38.0f;
        extreme = clampf(1.0f - over / 15.0f, 0.15f, 1.0f);
    }

    float score = combined * rh_factor * extreme;

    if (!isfinite(score)) {
        return 0.0f;
    }

    return clampf(score, 0.0f, 1.0f);
}
