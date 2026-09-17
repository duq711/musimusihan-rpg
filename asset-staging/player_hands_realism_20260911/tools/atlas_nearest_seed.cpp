// Exact squared Euclidean nearest-seed field; modifies no authored texels.
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <vector>
int main(int argc, char** argv) {
    if (argc != 5) return 2;
    const int w=std::stoi(argv[1]), h=std::stoi(argv[2]), inf=1000000000;
    const size_t count=size_t(w)*h;
    std::vector<uint8_t> mask(count);
    std::ifstream input(argv[3],std::ios::binary);
    input.read(reinterpret_cast<char*>(mask.data()),count);
    if(size_t(input.gcount())!=count) return 3;
    std::vector<int> nearest_x(count,-1), distance_x(count,inf);
    for(int y=0;y<h;y++) {
        int seed=-1;
        for(int x=0;x<w;x++) {
            const size_t i=size_t(y)*w+x;
            if(mask[i]) seed=x;
            if(seed>=0) {nearest_x[i]=seed;distance_x[i]=(x-seed)*(x-seed);}
        }
        seed=-1;
        for(int x=w-1;x>=0;x--) {
            const size_t i=size_t(y)*w+x;
            if(mask[i]) seed=x;
            if(seed>=0 && (seed-x)*(seed-x)<distance_x[i]) {
                nearest_x[i]=seed;distance_x[i]=(seed-x)*(seed-x);
            }
        }
    }
    std::vector<uint32_t> output(count);
    std::vector<int> v(h);
    std::vector<double> z(h+1);
    for(int x=0;x<w;x++) {
        int k=-1;
        for(int q=0;q<h;q++) {
            const int fq=distance_x[size_t(q)*w+x];
            if(fq>=inf) continue;
            if(k<0) {k=0;v[0]=q;z[0]=-INFINITY;z[1]=INFINITY;continue;}
            double s;
            while(true) {
                const int vk=v[k];
                s=(double(fq)+double(q)*q-distance_x[size_t(vk)*w+x]-double(vk)*vk)/(2.*(q-vk));
                if(s>z[k]) break;
                if(--k<0) break;
            }
            if(k<0) {k=0;v[0]=q;z[0]=-INFINITY;z[1]=INFINITY;}
            else {++k;v[k]=q;z[k]=s;z[k+1]=INFINITY;}
        }
        if(k<0) return 4;
        k=0;
        for(int y=0;y<h;y++) {
            while(z[k+1]<y) ++k;
            const int sy=v[k], sx=nearest_x[size_t(sy)*w+x];
            if(sx<0 || !mask[size_t(sy)*w+sx]) return 5;
            output[size_t(y)*w+x]=uint32_t(size_t(sy)*w+sx);
        }
    }
    std::ofstream file(argv[4],std::ios::binary);
    file.write(reinterpret_cast<const char*>(output.data()),count*sizeof(uint32_t));
    std::cout << "NEAREST_SEED_FIELD_COMPLETE " << count << "\n";
}
