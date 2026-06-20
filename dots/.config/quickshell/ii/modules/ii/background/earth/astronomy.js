.pragma library

function calculateAstronomy(ms_since_epoch, lon_rad) {
    // 1. Julian Date
    let jd = (ms_since_epoch / 86400000.0) + 2440587.5;
    let d = jd - 2451545.0; // Days since J2000.0
    let T = d / 36525.0; // Julian Centuries
    
    // 2. Mean Obliquity of the Ecliptic (Laskar's formula approximation)
    let eps0 = 23.43929111 - 0.013004167 * T - 0.000000164 * T*T + 0.0000005036 * T*T*T;
    let eps_rad = eps0 * Math.PI / 180.0;
    
    // 3. Sun Position (Simplified VSOP / Keplarian)
    let L = (280.46646 + 36000.76983 * T + 0.0003032 * T*T) % 360.0;
    let g = (357.52911 + 35999.05029 * T - 0.0001537 * T*T) % 360.0;
    let L_rad = L * Math.PI / 180.0;
    let g_rad = g * Math.PI / 180.0;
    
    let sun_lambda = L + 1.914602 * Math.sin(g_rad) + 0.019993 * Math.sin(2*g_rad);
    let sun_lam_rad = sun_lambda * Math.PI / 180.0;
    
    // Sun Right Ascension and Declination
    let sun_ra = Math.atan2(Math.cos(eps_rad) * Math.sin(sun_lam_rad), Math.cos(sun_lam_rad));
    let sun_dec = Math.asin(Math.sin(eps_rad) * Math.sin(sun_lam_rad));
    
    // 4. Moon Position
    let moon_L = (218.3164477 + 481267.88123421 * T) % 360.0;
    let moon_M = (134.9633964 + 477198.8675055 * T) % 360.0;
    let moon_F = (93.2720950 + 483202.0175233 * T) % 360.0;
    let moon_L_rad = moon_L * Math.PI / 180.0;
    let moon_M_rad = moon_M * Math.PI / 180.0;
    let moon_F_rad = moon_F * Math.PI / 180.0;
    
    let moon_lambda = moon_L + 6.289 * Math.sin(moon_M_rad);
    let moon_beta = 5.128 * Math.sin(moon_F_rad);
    let moon_lam_rad = moon_lambda * Math.PI / 180.0;
    let moon_bet_rad = moon_beta * Math.PI / 180.0;
    
    let moon_ra = Math.atan2(Math.sin(moon_lam_rad) * Math.cos(eps_rad) - Math.tan(moon_bet_rad) * Math.sin(eps_rad), Math.cos(moon_lam_rad));
    let moon_dec = Math.asin(Math.sin(moon_bet_rad) * Math.cos(eps_rad) + Math.cos(moon_bet_rad) * Math.sin(eps_rad) * Math.sin(moon_lam_rad));
    
    // 5. Earth Rotation Angle (ERA) / Greenwich Mean Sidereal Time (GMST)
    // Era is directly proportional to UT1. Using simple UT1 approx.
    let h = (ms_since_epoch % 86400000) / 3600000.0;
    let gmst = 6.697374558 + 0.06570982441908 * d + 1.00273790935 * h;
    let gmst_rad = ((gmst % 24.0) / 24.0) * 2 * Math.PI;
    
    return {
        sun_ra: sun_ra,
        sun_dec: sun_dec,
        moon_ra: moon_ra,
        moon_dec: moon_dec,
        gmst_rad: gmst_rad,
        eps_rad: eps_rad
    };
}
