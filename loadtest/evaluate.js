// Load test for the evaluation-service (hot path) through the Ingress.
// Usage:
//   k6 run -e BASE_URL=http://<load-balancer-dns> -e FLAG=black-friday loadtest/evaluate.js
// Watch the autoscaling in another terminal:
//   kubectl get hpa -n togglemaster-app -w
import http from "k6/http";
import { check } from "k6";

const BASE_URL = __ENV.BASE_URL;
const FLAG = __ENV.FLAG || "black-friday";

export const options = {
  stages: [
    { duration: "30s", target: 20 }, // ramp up
    { duration: "3m", target: 50 }, // sustained load -> HPA scales out
    { duration: "30s", target: 0 }, // ramp down -> HPA scales in after ~1 min
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],
  },
};

export default function () {
  const user = `user-${Math.floor(Math.random() * 100000)}`;
  const res = http.get(`${BASE_URL}/evaluate?user_id=${user}&flag_name=${FLAG}`);
  check(res, { "status 200": (r) => r.status === 200 });
}
