#include "eco_engine.h"
#include <math.h>

void grid_status_from_co2_intensity(float co2_g_per_kwh, GridStatus *out) {
    if (!out) {
        return;
    }

    float c = co2_g_per_kwh;
    if (!isfinite(c) || c < 0.0f) {
        c = 0.0f;
    }

    out->co2_intensity = c;

    if (c < 150.0f) {
        out->recommendation_level = 0;
    } else if (c <= 400.0f) {
        out->recommendation_level = 1;
    } else {
        out->recommendation_level = 2;
    }
}
