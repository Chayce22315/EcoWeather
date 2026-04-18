#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EcoDecisionModel : NSObject
@property (nonatomic) float ventilationScore;
@property (nonatomic) float co2Intensity;
@property (nonatomic) int recommendationLevel;
@property (nonatomic) int finalAction;
@property (nonatomic, copy) NSString *recommendation;
@end

@interface EcoEngine : NSObject
- (float)calculateVentilationScoreWithOutdoorTemp:(float)outdoorTemp
                                       indoorTemp:(float)indoorTemp
                                         humidity:(float)humidity;

- (EcoDecisionModel *)computeDecisionWithOutdoorTemp:(float)outdoorTemp
                                          indoorTemp:(float)indoorTemp
                                            humidity:(float)humidity
                                        co2Intensity:(float)co2;
@end

NS_ASSUME_NONNULL_END
