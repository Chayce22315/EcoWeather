#include "eco_engine.h"
#include <stdio.h>
#include <string.h>

static void fill_recommendation(EcoDecision *d) {
    if (!d) {
        return;
    }

    const char *msg = "Adjust heating and cooling based on current conditions.";
    int level = d->grid.recommendation_level;
    int action = d->final_action;

    if (action == 2) {
        if (level == 2) {
            msg = "Delay energy use if possible; grid carbon intensity is high.";
        } else {
            msg = "Use minimal energy; conditions favor waiting before heavy loads.";
        }
    } else if (action == 1) {
        msg = "Good time to open windows for passive ventilation.";
        if (level == 1) {
            msg = "Opening windows may help; consider delaying non-essential electric loads.";
        }
    } else {
        if (level == 0) {
            msg = "HVAC or active conditioning is reasonable; grid is relatively clean.";
        } else if (level == 1) {
            msg = "Prefer efficient HVAC use; consider delaying non-essential usage.";
        } else {
            msg = "Limit discretionary energy use; rely on efficient conditioning choices.";
        }
    }

    snprintf(d->recommendation, sizeof(d->recommendation), "%s", msg);
    d->recommendation[sizeof(d->recommendation) - 1] = '\0';
}

void compute_eco_decision(
    float outdoorTemp,
    float indoorTemp,
    float humidity,
    float co2_g_per_kwh,
    EcoDecision *out
) {
    if (!out) {
        return;
    }

    memset(out, 0, sizeof(EcoDecision));

    float v = calculate_eco_ventilation_score(outdoorTemp, indoorTemp, humidity);
    out->ventilation_score = v;

    grid_status_from_co2_intensity(co2_g_per_kwh, &out->grid);

    int level = out->grid.recommendation_level;

    if (level == 2) {
        out->final_action = 2;
    } else {
        if (v > 0.7f) {
            out->final_action = 1;
        } else {
            out->final_action = 0;
        }
    }

    fill_recommendation(out);
}
