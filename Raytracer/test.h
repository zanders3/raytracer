//
//  test.h
//  Raytracer
//
//  Created by Alex Parker on 04/01/2015.
//  Copyright (c) 2015 Alex Parker. All rights reserved.
//

#ifndef Raytracer_test_h
#define Raytracer_test_h

struct vec3 {
    float x, y, z;
};

struct tri {
    struct vec3 v1, v2, v3, N;
};

struct scene {
    struct tri* triangles;
    int numTris;
};

#endif
