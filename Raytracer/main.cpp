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
#include <float.h>
#include "objloader.h"

color* image;

static const int imageWidth = 800, imageHeight = 600, maxDepth = 3;

struct Ray
{
    vec3 origin, direction;
    
    Ray(vec3 origin, vec3 direction) : origin(origin), direction(direction)
    {
    }
};

struct Material
{
    float reflect, diffuse, spec;
    vec3 color;
    
    Material() : reflect(0.0f), diffuse(1.0f), spec(1.0f), color(vec3(1.0f,1.0f,1.0f))
    { }
};

struct Primitive
{
    Material material;
    const char* name;
    bool isLight = false;
    
    virtual bool Raycast(const Ray& ray, float& intersection) = 0;
    virtual vec3 GetNormal(const vec3& pos) = 0;
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
        
        intersection = distToCenter - sqrtf(radiusSq - distToIntersectSq);
        return true;
    }
    
    virtual vec3 GetNormal(const vec3& pos)
    {
        return (pos - this->pos).normalize();
    }
};

struct Plane : Primitive
{
    vec3 normal;
    float offset;
    
    Plane(vec3 normal, float offset) : normal(normal), offset(offset)
    {}
    
    virtual bool Raycast(const Ray& ray, float& intersection)
    {
        float ldotn = normal.dot(ray.direction);
        if (ldotn == 0.0f)
            return false;
        
        intersection = (offset - normal.dot(ray.origin)) / ldotn;
        return intersection > 0.0f;
    }
    
    virtual vec3 GetNormal(const vec3& pos)
    {
        return normal;
    }
};

struct Triangle : Primitive
{
    vec3 v1, e1, e2, N;
    
    Triangle(vec3 v1, vec3 v2, vec3 v3) : v1(v1), e1(v2-v1), e2(v3-v1)
    {
        N = e1.cross(e2).normalize();
    }
    
    virtual bool Raycast(const Ray& ray, float& intersection)
    {
        vec3 P = ray.direction.cross(e2);
        float det = e1.dot(P);
        if (det > -0.0001f && det < 0.0001f)
            return false;
        float invdet = 1.0f/det;
        
        vec3 T = ray.origin - v1;
        float u = T.dot(P) * invdet;
        if (u < 0.0f || u > 1.0f)
            return false;
        
        vec3 Q = T.cross(e1);
        float v = ray.direction.dot(Q) * invdet;
        if (v < 0.0f || u + v > 1.0f)
            return false;
        
        intersection = e2.dot(Q) * invdet;
        return intersection > 0.0001f;
    }
    
    virtual vec3 GetNormal(const vec3& pos)
    {
        return N;
    }
};

std::vector<Primitive*> scene;

float clamp01(float f)
{
    return f < 0.0f ? 0.0f : (f > 1.0f ? 1.0f : f);
}

vec3 raytrace(const Ray& r, int depth)
{
    //find nearest intersection
    float nearestIntersection = FLT_MAX, intersection;
    Primitive* nearestPrimitive = nullptr;
    for (auto iter = scene.begin(); iter != scene.end(); iter++)
    {
        if ((*iter)->Raycast(r, intersection) && nearestIntersection > intersection)
        {
            nearestIntersection = intersection;
            nearestPrimitive = *iter;
        }
    }
    
    //nothing hit, render BG color
    if (!nearestPrimitive)
        return vec3();
    
    vec3 col;
    vec3 pos = r.origin + r.direction * nearestIntersection;
    vec3 N = nearestPrimitive->GetNormal(pos);
    
    if (nearestPrimitive->isLight)
        col = nearestPrimitive->material.color;
    else
    {
        for (auto iter = scene.begin(); iter != scene.end(); iter++)
        {
            Primitive* p = *iter;
            if (p->isLight)
            {
                float shade = 1.0f;
                
                //Shadows
                vec3 L = (((Sphere*)p)->pos - pos).normalize();
                Ray shadowRay(pos + L * 0.01f, L);
                float shadowIntersection;
                for (auto iter = scene.begin(); iter != scene.end(); iter++)
                {
                    if (!(*iter)->isLight && (*iter)->Raycast(shadowRay, shadowIntersection))
                    {
                        shade = 0.0f;
                        break;
                    }
                }
                
                //N dot L diffuse lighting
                if (nearestPrimitive->material.diffuse > 0.0f)
                {
                    float diffuse = N.dot(L) * nearestPrimitive->material.diffuse;
                    col += (p->material.color * nearestPrimitive->material.color * diffuse) * shade;
                }
                
                //specular component
                if (nearestPrimitive->material.spec > 0.0f)
                {
                    vec3 R = L - N * L.dot(N) * 2.0f;
                    float dot = r.direction.dot(R);
                    if (dot > 0.0f)
                        col += p->material.color * nearestPrimitive->material.color * powf(dot, 20.0f) * nearestPrimitive->material.spec * shade;
                }
            }
        }
        
        if (nearestPrimitive->material.reflect > 0.0f && depth < maxDepth)
        {
            vec3 R = r.direction - N * 2.0f * r.direction.dot(N);
            vec3 reflectCol = raytrace(Ray(pos, R), depth+1);
            col += reflectCol * nearestPrimitive->material.color * nearestPrimitive->material.reflect;
        }
    }

    return col;
}

void LoadModel(const char* model)
{
    std::vector<vec3> verts;
    std::vector<vec2> uvs;
    std::vector<vec3> normals;
    std::vector<int> inds;
    
    LoadModel(model, verts, uvs, normals, inds);
    
    for (int i = 0; i<inds.size();i+=3)
    {
        scene.push_back(new Triangle(verts[inds[i]], verts[inds[i+1]], verts[inds[i+2]]));
    }
}

void setup()
{
    texturerenderer_setup();
    
    clock_t start = clock();
    
    Sphere* s = new Sphere(vec3(0.0f, 0.0f, 0.0f), 2.5f);
    s->material.reflect = 1.0f;
    s->material.diffuse = 0.0f;
    scene.push_back(s);
    
    s = new Sphere(vec3(2.0f, 5.0f, 1.0f), 0.1f);
    s->material.color = vec3(0.7f,0.7f,0.9f);
    s->isLight = true;
    scene.push_back(s);

    s = new Sphere(vec3(-2.0f, 5.0f, -3.0f), 0.1f);
    s->material.color = vec3(0.9f,0.9f,0.4f);
    s->isLight = true;
    scene.push_back(s);
    
    scene.push_back(new Plane(vec3(0.0f, 1.0f, 0.0f), -4.0f));
    
    //LoadModel("/Users/alex/repos/native/Raytracer/Raytracer/sponza.obj");
    
    image = new color[imageWidth*imageHeight];
    
    printf("Rendering...\n");
    for (int y = 0; y<imageHeight; y++)
    {
        for (int x = 0; x<imageWidth; x++)
        {
            //compute camera ray
            vec3 o(0.0f, 0.0f, -5.0f);
            float offsetX = x * 0.01f - 4.0f;
            float offsetY = y * 0.01f - 4.0f;
            Ray r(o, (vec3(offsetX, offsetY, 0.0f) - o).normalize());

            vec3 col = raytrace(r, 0);
            image[(y*imageWidth)+x] = (color){ (char)(clamp01(col.x)*255.0f), (char)(clamp01(col.y)*255.0f), (char)(clamp01(col.z)*255.0f) };
        }
        
        printf("\r%d/%d            ", y, imageHeight);
    }
    
    printf("\rRender took %f seconds", ((clock()-start)/(double)CLOCKS_PER_SEC));
    
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
