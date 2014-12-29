//
//  main.c
//  Raytracer
//
//  Created by Alex Parker on 29/12/2014.
//  Copyright (c) 2014 Alex Parker. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "glwt.h"

const char* vertShaderCode = "#version 330\n\
layout(location = 0) in vec3 pos;\n\
layout(location = 1) in vec2 coord;\n\
out vec2 coords;\n\
void main(){\n\
    coords=coord.xy;\n\
    gl_Position=vec4(pos, 1.0);\n\
}";

const char* fragShaderCode = "#version 330 core\n\
uniform sampler2D tex;\n\
in vec2 coords;\n\
out vec4 fragColor;\n\
void main(){\n\
    fragColor=texture(tex,coords);\n\
}";

#define BUFFER_OFFSET(offset) (const void*)(offset)

struct color {
    char r, g, b;
};

void setup()
{
    //Compile shader code
    GLint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    GLint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
    int vertLen = (int)strlen(vertShaderCode);
    int fragLen = (int)strlen(fragShaderCode);
    glShaderSource(vertexShader, 1, &vertShaderCode, &vertLen);
    glShaderSource(fragmentShader, 1, &fragShaderCode, &fragLen);
    glCompileShader(vertexShader);
    glCompileShader(fragmentShader);
    
    GLint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    glUseProgram(program);
    
    //Create the vertex buffers
    GLuint vertexBuffer;
    float verts[] = {
        -1.0f, -1.0f, 0.0f,
        1.0f, -1.0f, 0.0f,
        1.0f, 1.0f, 0.0f,
        -1.0f, 1.0f, 0.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f, 1.0f
    };
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(verts), &verts, GL_STATIC_DRAW);
    
    //Create the vertex layout
    GLuint vertexLayout;
    glGenVertexArrays(1, &vertexLayout);
    glBindVertexArray(vertexLayout);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, BUFFER_OFFSET(sizeof(float)*3*4));
    glEnableVertexAttribArray(1);
    
    //Setup texture
    struct color* textureData = (struct color*)malloc(sizeof(struct color)*512*512);
    for (int i = 0; i<512*512; i++) {
        struct color col = { 0, 0, 255 };
        textureData[i] = col;
    }
    
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 512, 512, 0, GL_RGB, GL_UNSIGNED_BYTE, textureData);
    free(textureData);
    
    glActiveTexture(GL_TEXTURE0);
    glUniform1i(glGetUniformLocation(program, "tex"), 0);
    glBindTexture(GL_TEXTURE_2D, texture);
}

void draw(float time)
{
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
}

int main(int argc, char *argv[])
{
    return initglwt("Raytracer", 800, 600, false);
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
