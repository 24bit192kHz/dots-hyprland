vec3 earthNorm = rotateX(sphereNorm, -cameraTilt);
vec3 np = vec3(0.0, 1.0, 0.0);
vec3 sunVec = baseSunVec;
vec3 greenwichVec = baseGreenwichVec;
vec3 eastVec = baseEastVec;
float nDotL = dot(earthNorm, sunVec);
vec3 viewVecTrue = rotateX(vec3(0.0, 0.0, 1.0), -cameraTilt);
vec3 halfVec = normalize(sunVec + viewVecTrue);
