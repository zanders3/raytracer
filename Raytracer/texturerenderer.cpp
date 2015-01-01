//
//  texturerenderer.c
//  Raytracer
//
//  Created by Alex Parker on 29/12/2014.
//  Copyright (c) 2014 Alex Parker. All rights reserved.
//

#include "texturerenderer.h"
#include "glwt.h"
#include <string>

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

GLuint texture;

void texturerenderer_setup()
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
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glActiveTexture(GL_TEXTURE0);
    glUniform1i(glGetUniformLocation(program, "tex"), 0);
    glBindTexture(GL_TEXTURE_2D, texture);
}

void texturerenderer_displaytexture(color* pixels, int w, int h)
{
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, w, h, 0, GL_RGB, GL_UNSIGNED_BYTE, pixels);
}

void texturerenderer_draw()
{
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
}
