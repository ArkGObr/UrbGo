export interface GeminiAlert {
  type: string;
  severity: string;
  location: string;
  affectsRoute: boolean;
  delayEstimateSeconds: number;
}

export interface GeminiRoutingResponse {
  optimizedRoute: {
    polyline: string;
    distanceMeters: number;
    durationSeconds: number;
    durationInTrafficSeconds: number;
  };
  eta: string;
  trafficRatio: number;
  alerts: GeminiAlert[];
  tollCost: {
    totalBRL: number;
    breakdown: Array<{ name: string; valueBRL: number }>;
  };
}
