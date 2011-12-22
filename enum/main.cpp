#include <stdio.h>
#include <math.h>
#include <set>
using namespace std;

// Enumerating all possible wire combinations
// f1 - first diode module
// f2 - second diode module

void f1(bool a[4]) {
	a[1] |= a[0];
	a[2] |= a[1];
	a[2] |= a[3];
}

void f2(bool a[4]) {
	a[1] |= a[2];
	a[0] |= a[1];
	a[3] |= a[2];
}

typedef void (*func)(bool a[4]);

int calc(func f, int perm[4], int power) {
	bool a[4];
	for (int i=0;i<4;i++) a[i] = false;
	a[perm[power]] = true;
	f(a);
	a[perm[power]] = false;
	int res = 0;
	for (int i=0;i<4;i++) {
		res <<= 1;
		if (a[perm[i]]) res |= 1;
	}
	return res;
}

int calcall(func f, int perm[4]) {
	int res = 0;
	for (int power=0; power<4; power++) {
		res <<= 4;
		res |= calc(f, perm, power);
	}
	return res;
}

int perms[24][4] = {
	0,1,2,3,
	0,1,3,2,
	0,2,1,3,
	0,2,3,1,
	0,3,1,2,
	0,3,2,1,
	1,0,2,3,
	1,0,3,2,
	1,2,0,3,
	1,2,3,0,
	1,3,0,2,
	1,3,2,0,
	2,0,1,3,
	2,0,3,1,
	2,1,0,3,
	2,1,3,0,
	2,3,0,1,
	2,3,1,0,
	3,0,1,2,
	3,0,2,1,
	3,1,0,2,
	3,1,2,0,
	3,2,0,1,
	3,2,1,0
};

int main() {
	set<int> s;
	for (int i=0;i<24;i++) {
		int res = calcall(f1, perms[i]);
		if (s.find(res) != s.end()) {
			printf("FAIL!!!!\n");
		}
		s.insert(res);
		printf("F1 %d %d %d %d %04X\n", perms[i][0], perms[i][1], perms[i][2], perms[i][3], res);
	}
	for (int i=0;i<24;i++) {
		int res = calcall(f2, perms[i]);
		if (s.find(res) != s.end()) {
			printf("FAIL!!!!\n");
		}
		s.insert(res);
		printf("F2 %d %d %d %d %04X\n", perms[i][0], perms[i][1], perms[i][2], perms[i][3], res);
	}
}

