# render3d — fixed-point software rasterizer, spinning cubes
Screen 320x240, frames = argv[1] (default 120). Integers only; `fdiv(a, b)` = floor division,
`fmod` = Euclidean remainder (GPLM's `/` and `%`; C/Rust use explicit helpers).
sin(a) = SINES[fmod(a, 256)] (the 256-entry table x4096 from apps/demo3d), cos(a) = sin(a + 64).
Cube: vertices (±100, ±100, ±100) in order (-,-,-),(+,-,-),(+,+,-),(-,+,-),(-,-,+),(+,-,+),(+,+,+),(-,+,+);
12 triangles (vertex indices) with colors c[k] = FACECOL[k/2]:
[0,1,2],[0,2,3] [5,4,7],[5,7,6] [4,0,3],[4,3,7] [1,5,6],[1,6,2] [3,2,6],[3,6,7] [4,5,1],[4,1,0];
FACECOL = [0xE04040, 0x40E040, 0x4040E0, 0xE0E040, 0x40E0E0, 0xE040E0].
Cubes i = 0..3 at offsets ox = -240 + 160*i, oz = 0; angles ay = 3*t + 40*i, ax = 2*t + 17*i.
Vertex transform: rotate Y: x1 = fdiv(x*cos(ay) + z*sin(ay), 4096), z1 = fdiv(z*cos(ay) - x*sin(ay), 4096);
rotate X: y2 = fdiv(y*cos(ax) - z1*sin(ax), 4096), z2 = fdiv(y*sin(ax) + z1*cos(ax), 4096);
world: X = x1 + ox, Y = y2, Z = z2 + 700. Project: sx = 160 + fdiv(X*256, Z), sy = 120 - fdiv(Y*256, Z).
Triangle (a,b,c projected): area = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax); skip if area >= 0 (back-face).
depth = Za + Zb + Zc; draw visible triangles of all cubes sorted by depth descending (farthest first,
ties: earlier cube, then earlier triangle). Shade: color channels ch * s / 256 with
s = clamp(512 - fdiv(depth, 8), 64, 256) (per channel: fdiv(ch*s, 256)).
Fill: for y = max(0, ymin)..min(239, ymax): x-span of the triangle at row y = min/max over the three
edges (p,q) with p.y != q.y and y between them (inclusive) of x = p.x + fdiv((y - p.y)*(q.x - p.x), q.y - p.y);
fill x from max(0, xl) to min(319, xr); later triangles overwrite. Background 0.
Frame checksum: sum over y, x of pix * (x + 1 + y) mod 1000000007; total = (total*7 + frame) mod 1000000007.
Print `checksum <total>`.
