
#include "test.h"

kernel void square(global struct scene* input, global float* output) {
    size_t p = get_global_id(0);
    
    for (int i = 0; i<input->numTris; i++)
    {
        struct tri* triangle = &input->triangles[i];
        output[p] += triangle->v1.x;
    }
}
