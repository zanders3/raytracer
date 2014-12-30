//
//  texturerenderer.h
//  Raytracer
//
//  Created by Alex Parker on 29/12/2014.
//  Copyright (c) 2014 Alex Parker. All rights reserved.
//

#ifndef __Raytracer__texturerenderer__
#define __Raytracer__texturerenderer__

#include <stdio.h>

struct color {
    char r, g, b;
};

void texturerenderer_setup();
void texturerenderer_displaytexture(color* pixels, int w, int h);
void texturerenderer_draw();

#endif /* defined(__Raytracer__texturerenderer__) */
