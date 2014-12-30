/**
 * Copyright Alex Parker 2013
 *
 * OpenGL Window Toolkit Header File
 *
 * This header file contains vec3, mat4 data structures and associated operations.
 **/

#ifndef __glwt_math_h
#define __glwt_math_h

#include <math.h>

#ifdef WIN32
#define M_PI 3.14159265f
#endif

//converts radians to degrees
inline float rad2deg(float radians)
{
    return radians * (180.0f/M_PI);
}

//converts degrees to radians
inline float deg2rad(float deg)
{
    return (deg * M_PI) / 180.0f;
}

//represents a 2D vector
struct vec2
{
    float x, y;
    
    vec2() : x(0.0f), y(0.0f)
    {
    }
    
    vec2(float x, float y) : x(x), y(y)
    {
    }
    
    //multiplies the vector by a scalar, returning the result.
    inline vec2 operator *(const float scalar) const
    {
        return vec2(x * scalar, y * scalar);
    }
    
    //adds two vectors together, returning the result.
    inline vec2 operator +(const vec2& other) const
    {
        return vec2(x + other.x, y + other.y);
    }
    
    //subtracts two vectors, returning the result.
    inline vec2 operator -(const vec2& other) const
    {
        return vec2(x - other.x, y - other.y);
    }
    
    //calculate the dot product with the other vector, returning the result.
    inline float dot(const vec2& other) const
    {
        return x*other.x + y*other.y;
    }
    
    //calculates the squared length of the current vector.
    inline float lengthSq() const
    {
        return dot(*this);
    }
    
    //calculates the length of the vector.
    inline float length() const
    {
        return sqrtf(lengthSq());
    }
    
    //normalizes the current vector.
    void normalize()
    {
        float len = length();
        x /= len;
        y /= len;
    }
};

//represents a 3D vector
struct vec3
{
    float x, y, z;
    
    vec3() : x(0.0f), y(0.0f), z(0.0f)
    {
    }
    
    vec3(float x, float y, float z) : x(x), y(y), z(z)
    {
    }
    
    //multiplies the vector by a scalar, returning the result.
    inline vec3 operator *(const float scalar) const
    {
        return vec3(
                    x * scalar, y * scalar, z * scalar
                    );
    }
    
    //adds two vectors together, returning the result.
    inline vec3 operator +(const vec3& other) const
    {
        return vec3(
                    x + other.x, y + other.y, z + other.z
                    );
    }
    
    //subtracts two vectors, returning the result.
    inline vec3 operator -(const vec3& other) const
    {
        return vec3(
                    x - other.x, y - other.y, z - other.z
                    );
    }
    
    //calculate the dot product with the other vector, returning the result.
    inline float dot(const vec3& other) const
    {
        return x*other.x + y*other.y + z*other.z;
    }
    
    //calculates the squared length of the current vector.
    inline float lengthSq() const
    {
        return dot(*this);
    }
    
    //calculates the length of the vector.
    inline float length() const
    {
        return sqrtf(lengthSq());
    }
    
    //normalizes the current vector.
    vec3 normalize()
    {
        float len = length();
        return vec3(x/len,y/len,z/len);
    }
    
    //calculates the cross product with the other vector, returning the result.
    inline vec3 cross(const vec3& other) const
    {
        return vec3(
                    y*other.z - z*other.y,
                    z*other.x - x*other.z,
                    x*other.y - y*other.x
                    );
    }
};

//represents a 4x4 matrix
struct mat4
{
    float rows[16];
    
    //performs a matrix multiplication and returns the result.
    mat4 operator *(const mat4& other) const
    {
        mat4 res;
        for (int i = 0; i<16; i+=4)
            for (int j = 0; j<4; j++)
                res.rows[i+j] =
                other.rows[i]*rows[j] +
                other.rows[i+1]*rows[j+4] +
                other.rows[i+2]*rows[j+8] +
                other.rows[i+3]*rows[j+12];
        
        return res;
    }
    
    //produces a axis angle matrix. This will produce a rotation in radians about the normalized axis.
    static mat4 axisangle(const vec3& axis, float angle)
    {
        float c = cosf(angle), ic = 1.0f - c;
        float s = sinf(angle);
        mat4 mat = {{
            c+ic*axis.x*axis.x,         ic*axis.x*axis.y-axis.z*s,  ic*axis.x*axis.z+axis.y*s, 0.0f,
            ic*axis.x*axis.y+axis.z*s,  c+ic*axis.y*axis.y,         ic*axis.y*axis.z-axis.x*s, 0.0f,
            ic*axis.x*axis.z-axis.y*s,  ic*axis.y*axis.z+axis.x*s,  c+ic*axis.z*axis.z,        0.0f,
            0.0f,                       0.0f,                       0.0f,                      1.0f
        }};
        return mat;
    }
    
    //produces a translation matrix
    static mat4 translate(float x, float y, float z)
    {
        mat4 mat = {{
            1.0f, 0.0f, 0.0f, x,
            0.0f, 1.0f, 0.0f, y,
            0.0f, 0.0f, 1.0f, z,
            0.0f, 0.0f, 0.0f, 1.0f
        }};
        return mat;
    }
    
    //returns the identity matrix
    static mat4 identity()
    {
        mat4 mat = {{
            1.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 1.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 1.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 1.0f
        }};
        return mat;
    }
    
    //calculates a projection matrix from the field of view in radians,
    //the aspect ratio, the near culling plane and far culling plane.
    static mat4 proj(float fov, float aspect, float n, float f)
    {
        float yScale = 1.0f/tanf(fov*0.5f);
        float xScale = yScale / aspect;
        
        mat4 mat = {{
            xScale, 0.0f,   0.0f, 0.0f,
            0.0f,   yScale, 0.0f, 0.0f,
            0.0f,   0.0f,   f/(f-n), (-f*n)/(f-n),
            0.0f,   0.0f,   1.0f, 0.0f
        }};
        return mat;
    }
};

#endif
