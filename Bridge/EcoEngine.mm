#import "EcoEngine.h"

extern "C" {
#include "eco_engine.h"
}

@implementation EcoDecisionModel
@end

@implementation EcoEngine

- (float)calculateVentilationScoreWithOutdoorTemp:(float)outdoorTemp
                                       indoorTemp:(float)indoorTemp
                                         humidity:(float)humidity {
    return calculate_eco_ventilation_score(outdoorTemp, indoorTemp, humidity);
}

- (EcoDecisionModel *)computeDecisionWithOutdoorTemp:(float)outdoorTemp
                                          indoorTemp:(float)indoorTemp
                                            humidity:(float)humidity
                                        co2Intensity:(float)co2 {
    EcoDecision decision;
    compute_eco_decision(outdoorTemp, indoorTemp, humidity, co2, &decision);

    EcoDecisionModel *model = [[EcoDecisionModel alloc] init];
    model.ventilationScore = decision.ventilation_score;
    model.co2Intensity = decision.grid.co2_intensity;
    model.recommendationLevel = decision.grid.recommendation_level;
    model.finalAction = decision.final_action;
    model.recommendation = [NSString stringWithUTF8String:decision.recommendation];
    if (model.recommendation == nil) {
        model.recommendation = @"";
    }
    return model;
}

@end
