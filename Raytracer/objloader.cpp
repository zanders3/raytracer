//
//  objloader.cpp
//  Raytracer
//
//  Created by Alex Parker on 04/01/2015.
//  Copyright (c) 2015 Alex Parker. All rights reserved.
//

#include "objloader.h"
#include <string>
#include <iostream>
#include <fstream>
#include <sstream>
#include <assert.h>

using namespace std;

void LoadModel(const char *objFile, std::vector<vec3>& vertices, std::vector<vec2>& texcoords, std::vector<vec3>& normals, std::vector<int>& indices)
{
    string line;
    ifstream file(objFile);
    if (file.is_open())
    {
        while (getline(file, line, '\n'))
        {
            istringstream liness(line);
            getline(liness, line, ' ');
            
            if (line == "v")
            {
                string x, y, z;
                getline(liness, x, ' ');
                getline(liness, y, ' ');
                getline(liness, z, ' ');
                vertices.push_back(vec3(
                    (float)atof(x.c_str()),
                    (float)atof(y.c_str()),
                    (float)atof(z.c_str())
                ));
            }
            else if (line == "vt")
            {
                string u, v;
                getline(liness, u, ' ');
                getline(liness, v, ' ');
                
                texcoords.push_back(vec2(
                                         (float)atof(u.c_str()),
                                         (float)atof(v.c_str())
                                         ));
            }
            else if (line == "vn")
            {
                string x, y, z;
                getline(liness, x, ' ');
                getline(liness, y, ' ');
                getline(liness, z, ' ');
                normals.push_back(vec3(
                                       (float)atof(x.c_str()),
                                       (float)atof(y.c_str()),
                                       (float)atof(z.c_str())
                                       ));
            }
            else if (line == "f")
            {
                int inds[4];
                for (int i = 0; i<4; i++)
                {
                    string indBits;
                    getline(liness, indBits, ' ');
                    istringstream iss(indBits);
                    string bit;
                    
                    //Read Position
                    if (getline(iss, bit, '/'))
                    {
                        inds[i] = atoi(bit.c_str()) - 1;//indices are counted from 1 for some reason
                    }
                    //Failing to read at this point means
                    //this is a tri, not a quad.
                    else
                    {
                        assert(i == 3);//we should have failed to read the 4th position
                        inds[i] = -1;
                        
                        continue;
                    }
                }
                
                indices.push_back(inds[0]);
                indices.push_back(inds[1]);
                indices.push_back(inds[2]);
                
                if (inds[3] != -1)
                {
                    indices.push_back(inds[0]);
                    indices.push_back(inds[2]);
                    indices.push_back(inds[3]);
                }
            }
        }
    }
    
    file.close();
}
