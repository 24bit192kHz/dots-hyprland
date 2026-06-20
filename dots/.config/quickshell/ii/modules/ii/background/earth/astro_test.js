const ms = new Date('2026-06-18T11:03:27Z').getTime();
const daysSince2000 = (ms - 946728000000) / 86400000.0;

const now = new Date(ms);
const startOfYear = new Date(now.getFullYear(), 0, 1);
const dayOfYear = (now - startOfYear) / 86400000.0;

const sunOrbitAngle = ((dayOfYear - 79) / 365.25) * 2 * Math.PI + Math.PI;

const newMoonRef = new Date('2024-01-11T11:57:00Z').getTime();
const moonAgeDays = (ms - newMoonRef) / 86400000.0;
const moonPhase = (moonAgeDays % 29.530588) / 29.530588;
const moonOrbitAngle = sunOrbitAngle + moonPhase * 2 * Math.PI;

console.log("Date:", now.toISOString());
console.log("Day of year:", dayOfYear);
console.log("Sun Angle (deg):", sunOrbitAngle * 180 / Math.PI % 360);
console.log("Moon Phase:", moonPhase);
console.log("Moon Angle (deg):", moonOrbitAngle * 180 / Math.PI % 360);

const utcDays = ms / 86400000.0;
let baseEarthAngle = 0.5 - (utcDays % 1.0) - (sunOrbitAngle / (2 * Math.PI));
console.log("Base Earth Angle:", baseEarthAngle % 1.0);
