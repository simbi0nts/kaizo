# game — headless Snake with a deterministic AI
Grid 32x24. RNG: r = (r * 1103515245 + 12345) mod 2^31, seed 42.
New game: body (16,12),(15,12),(14,12) (head first), direction Right, score 0, then place food:
repeat { r = next(r); x = r mod 32; r = next(r); y = r mod 24 } until (x,y) is not on the body.
Each tick: candidates = [horizontal step toward food if food.x != head.x, vertical step toward food
if food.y != head.y, Up, Right, Down, Left] (Up = y-1). Take the first candidate that is not the
opposite of the current direction and whose target cell is inside the grid and not on the body
without its last segment; if none, keep the current direction. Move: if the new head is outside or
on the body without its last segment → game over: games += 1, total += score, start a new game
(RNG continues). Otherwise the head is added; if it is the food: score += 1 and place new food,
else the last segment is removed. checksum = (checksum * 31 + head.x * 32 + head.y) mod 1000000007
after every tick (using the new game's head after a restart).
Run TICKS = argv[1] (default 200000) ticks. Print: `games <g> total <total + score> checksum <c>`.
