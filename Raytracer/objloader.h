//
//  objloader.h
//  Raytracer
//
//  Created by Alex Parker on 04/01/2015.
//  Copyright (c) 2015 Alex Parker. All rights reserved.
//

#ifndef __Raytracer__objloader__
#define __Raytracer__objloader__

#include "maths.h"
#include <vector>

void LoadModel(const char *objFile, std::vector<vec3>& vertices, std::vector<vec2>& texcoords, std::vector<vec3>& normals, std::vector<int>& indices);

#endif /* defined(__Raytracer__objloader__) */
