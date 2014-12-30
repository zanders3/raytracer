//
//  main.c
//  Raytracer
//
//  Created by Alex Parker on 29/12/2014.
//  Copyright (c) 2014 Alex Parker. All rights reserved.
//

#include "glwt.h"
#include "texturerenderer.h"
#include "maths.h"
#include <vector>

color* image;

static const int imageWidth = 800, imageHeight = 600;

struct Ray
{
    vec3 origin, direction;
    
    Ray(vec3 origin, vec3 direction) : origin(origin), direction(direction)
    {
    }
};

struct Material
{
    float reflect, diffuse;
    vec3 color;
    
    Material() : reflect(0.0f), diffuse(1.0f), color(vec3(1.0f, 0.0f, 0.0f))
    { }
};

struct Primitive
{
    Material material;
    const char* name;
    
    virtual bool Raycast(const Ray& ray, float& intersection) = 0;
};

struct Sphere : Primitive
{
    vec3 pos;
    float radius, radiusSq;
    
    Sphere(vec3 pos, float radius) : pos(pos), radius(radius), radiusSq(radius*radius)
    {}
    
    virtual bool Raycast(const Ray& ray, float& intersection)
    {
        vec3 l = pos - ray.origin;//vector from sphere pos to ray origin
        float distToCenter = l.dot(ray.direction);
        if (distToCenter < 0.0f)//sphere behind ray
            return false;
        float distToIntersectSq = l.dot(l) - distToCenter * distToCenter;//pythagorous theorum to get intersection dist from sphere midpoint along ray
        if (distToIntersectSq > radiusSq)
            return false;
        
        intersection = distToCenter - sqrtf(distToIntersectSq);
        return true;
    }
};

#include <float.h>
std::vector<Primitive*> scene;

color raytrace(int x, int y)
{
    //compute camera ray
    vec3 o(0.0f, 0.0f, -5.0f);
    float offsetX = x * 0.01f - 4.0f;
    float offsetY = y * 0.01f - 4.0f;
    Ray r(o, (vec3(offsetX, offsetY, 0.0f) - o).normalize());
    
    //find nearest intersection
    float nearestIntersection = FLT_MAX, intersection;
    Primitive* nearestPrimitive = nullptr;
    for (auto iter = scene.begin(); iter != scene.end(); iter++)
    {
        if ((*iter)->Raycast(r, intersection) && nearestIntersection > intersection) {
            nearestIntersection = intersection;
            nearestPrimitive = *iter;
        }
    }
    
    if (!nearestPrimitive)
        return (color){ 0, 0, 0 };
    
    vec3 col = nearestPrimitive->material.color;
    return (color){ (char)(col.x*255.0f), (char)(col.y*255.0f), (char)(col.z*255.0f) };
}

void setup()
{
    texturerenderer_setup();
    
    scene.push_back(new Sphere(vec3(1.0f, -0.8f, 3.0f), 2.5f));
    scene.push_back(new Sphere(vec3(-5.5f,-0.5f, 7.0f), 2.0f));
    scene.push_back(new Sphere(vec3(0.0f, 5.0f, 5.0f), 0.1f));
    scene.push_back(new Sphere(vec3(2.0f, 5.0f, 1.0f), 0.1f));
    
    image = new color[imageWidth*imageHeight];
    
    for (int y = 0; y<imageHeight; y++)
        for (int x = 0; x<imageWidth; x++)
            image[(y*imageWidth)+x] = raytrace(x,y);
    
    texturerenderer_displaytexture(image, imageWidth, imageHeight);
}

void draw(float time)
{
    texturerenderer_draw();
}

int main(int argc, char *argv[])
{
    return initglwt("Raytracer", imageWidth, imageHeight, false);
}

/*int main(int argc, const char * argv[]) {
    char name[128];
    
    dispatch_queue_t queue = gcl_create_dispatch_queue(CL_DEVICE_TYPE_GPU, NULL);
    if (queue == NULL)
        queue = gcl_create_dispatch_queue(CL_DEVICE_TYPE_CPU, NULL);
    
    cl_device_id gpu = gcl_get_device_id_with_dispatch_queue(queue);
    clGetDeviceInfo(gpu, CL_DEVICE_NAME, 128, name, NULL);
    fprintf(stdout, "Using %s\n", name);
    
    float* testValues = (float*)malloc(sizeof(float)*NUM_VALUES);
    for (int i = 0; i<NUM_VALUES; i++)
        testValues[i] = (float)i;
    
    float* testResult = (float*)malloc(sizeof(float)*NUM_VALUES);
    void* memIn = gcl_malloc(sizeof(float)*NUM_VALUES, testValues, CL_MEM_READ_ONLY|CL_MEM_COPY_HOST_PTR);
    void* memOut = gcl_malloc(sizeof(float)*NUM_VALUES, NULL, CL_MEM_WRITE_ONLY);
    
    dispatch_sync(queue, ^{
        size_t wgs;
        gcl_get_kernel_block_workgroup_info(square_kernel, CL_KERNEL_WORK_GROUP_SIZE, sizeof(wgs), &wgs, NULL);
        
        cl_ndrange range = {
            1,//number of dimensions
            {0,0,0},//offset in each dimension
            {NUM_VALUES,0,0},//end offset in each dimension
            {wgs,0,0}//local size of each workgroup
        };
        square_kernel(&range,(cl_float*)memIn, (cl_float*)memOut);
        gcl_memcpy(testResult, memOut, sizeof(float)*NUM_VALUES);
    });
    
    if ( validate(testValues, testResult)) {
        fprintf(stdout, "All values were properly squared.\n");
    }
    
    gcl_free(memIn);
    gcl_free(memOut);
    free(testResult);
    free(testValues);
    
    dispatch_release(queue);
    
    return 0;
}*/
