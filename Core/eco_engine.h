#ifndef ECO_ENGINE_H
#define ECO_ENGINE_H

typedef struct {
    float co2_intensity;
    int recommendation_level;
} GridStatus;

typedef struct {
    float ventilation_score;
    GridStatus grid;
    int final_action;
    char recommendation[128];
} EcoDecision;

float calculate_eco_ventilation_score(float outdoorTemp, float indoorTemp, float humidity);

void grid_status_from_co2_intensity(float co2_g_per_kwh, GridStatus *out);

void compute_eco_decision(
    float outdoorTemp,
    float indoorTemp,
    float humidity,
    float co2_g_per_kwh,
    EcoDecision *out
);

#endif
