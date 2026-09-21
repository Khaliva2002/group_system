-- ecma Group System v2 - Turf module (server)
-- Memory-only: NO database. Everything lives in RAM and resets on restart.
-- Stage 1: zones definition + map drawing (radar) + entry detection (colshape).

-- ================= zones (RAM truth) =================
-- Each zone:
--   center   : middle point {x, y, z}
--   loyalty  : 0-100, how loyal the zone is to its owning gang (0 = none)
--   gang     : owning clan name (nil = nobody)
--   money    : money stored inside the zone
--   color    : {r, g, b} drawn on the map
--   stat     : zone status string ("neutral" for now)
--   position : map rect {x, y, z, w, h, dim} - x,y is corner 1 EXACT
--   radar    : radarArea element (created on start)
--   col      : colshape element (entry/exit events)
local zones = {
    [1] = {
        name = "air port",
        center  = { x = 1407.5800, y = 1536.7859, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 20000,
        color   = { r = 255, g = 255, b = 255 }, -- neutral white (test)
        stat    = false,
        position = {
            -- corner 1 anchor (EXACT as given):
            x = 1258.2661, y = 1210.9777, z = 10.8203,
            -- size computed from the 4 given corners:
            --   c2: 1543.2539, 1211.0140 | c3: 1556.8939, 1862.5941 | c4: 1258.0729, 1800.5031
            w = 298.6278, h = 593.6164,
            dim = 0,
        },
    },
        [2] = {
            name = "msn",
        center  = { x = 1067.6533, y = 1768.5049, z = 11.2717 },
        loyalty = 100,
        gang    = nil,
        money   = 3000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1017.6533, y = 1723.5049, z = 11.2717,
            w = 100.0000, h = 90.0000,
            dim = 0,
        },

    },
        [3] = {
        center  = { x = 1097.6553, y = 1552.8662, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 6500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1017.6553, y = 1382.8662, z = 10.8203,
            w = 160.0000, h = 340.0000,
            dim = 0,
        },
        name = "circle"
    },
     [4] = {
        center  = { x = 952.9229, y = 1736.0957, z = 11.6991 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 917.9229, y = 1623.5957, z = 11.6991,
            w = 82.0000, h = 225.0000,
            dim = 0,
        },
        name = "idk"
    },
    [5] = {
        center  = { x = 1076.7764, y = 1886.1611, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1016.7764, y = 1823.6611, z = 10.8203,
            w = 120.0000, h = 125.0000,
            dim = 0,
        },
        name = "baff"
    },
      [6] = {
        center  = { x = 956.1816, y = 2023.4043, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 2800,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 916.1816, y = 1863.4043, z = 10.8203,
            w = 80.0000, h = 320.0000,
            dim = 0,
        },
        name = "jinkz",
    },
     [7] = {
        center  = { x = 957.6113, y = 2293.3057, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 917.6113, y = 2203.3057, z = 10.8203,
            w = 80.0000, h = 180.0000,
            dim = 0,
        },
        name="jinwoa"
    },
        [8] = {
        center  = { x = 1097.6699, y = 2228.5049, z = 14.2671 },
        loyalty = 100,
        gang    = nil,
        money   = 5000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1017.6699, y = 2063.5049, z = 14.2671,
            w = 160.0000, h = 290.0000,
            dim = 0,
        },
        name = "buggy"
    },
     [9] = {
        center  = { x = 1097.0430, y = 2003.1934, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1017.0430, y = 1963.1934, z = 10.8203,
            w = 160.0000, h = 80.0000,
            dim = 0,
        },
        name = "z-index"
    },
      [10] = {
        center  = { x = 1055.2451, y = 1283.6191, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 3000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1017.7451, y = 1203.6191, z = 10.8203,
            w = 75.0000, h = 160.0000,
            dim = 0,
        },
        name = "sidden"
    },
        [11] = {
        center  = { x = 1136.4619, y = 1283.6260, z = 16.3110 },
        loyalty = 100,
        gang    = nil,
        money   = 3000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1098.9619, y = 1203.6260, z = 16.3110,
            w = 78.0000, h = 160.0000,
            dim = 0,
        },
        name = "killing"
    },
        [12] = {
        center  = { x = 1477.6074, y = 2013.8164, z = 12.3222 },
        loyalty = 100,
        gang    = nil,
        money   = 1000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1397.6074, y = 1983.8164, z = 12.3222,
            w = 160.0000, h = 60.0000,
            dim = 0,
        },
        name = "simo"
    },
     [13] = {
        center  = { x = 1352.0859, y = 2160.8594, z = 11.1304 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1297.0859, y = 2105.8594, z = 11.1304,
            w = 110.0000, h = 110.0000,
            dim = 0,
        },
        name = "square"
    },
      [14] = {
        center  = { x = 1474.9395, y = 2355.0029, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 1500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1394.9395, y = 2322.5029, z = 10.8203,
            w = 160.0000, h = 65.0000,
            dim = 0,
        },
        name = "class"
    },
        [15] = {
        center  = { x = 1649.9600, y = 2342.6533, z = 15.6102 },
        loyalty = 100,
        gang    = nil,
        money   = 3000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1577.4600, y = 2282.6533, z = 15.6102,
            w = 145.0000, h = 120.0000,
            dim = 0,
        },
        name = "SQF"
    },
        [16] = {
        center  = { x = 1314.4141, y = 2549.6328, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 1000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1249.4141, y = 2517.1328, z = 10.8203,
            w = 130.0000, h = 65.0000,
            dim = 0,
        },
        name = "opox"
    },
        [17] = {
        center  = { x = 1475.7090, y = 2799.5820, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 4000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1415.7090, y = 2724.5820, z = 10.8203,
            w = 120.0000, h = 160.0000,
            dim = 0,
        },
        name = "TOP"
    },
        [18] = {
        center  = { x = 1267.4502, y = 2794.5576, z = 10.8159 },
        loyalty = 100,
        gang    = nil,
        money   = 4600,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1122.4502, y = 2724.5576, z = 10.8159,
            w = 290.0000, h = 140.0000,
            dim = 0,
        },
        name = "OPA"
    },
        [19] = {
        center  = { x = 1617.2861, y = 2755.2021, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 2000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1552.2861, y = 2685.2021, z = 10.8203,
            w = 130.0000, h = 140.0000,
            dim = 0,
        },
        name = "Zarouk"
    },
       [20] = {
        center  = { x = 1797.5234, y = 2803.9365, z = 13.6413 },
        loyalty = 100,
        gang    = nil,
        money   = 4500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1697.5234, y = 2723.9365, z = 13.6413,
            w = 200.0000, h = 160.0000,
            dim = 0,
        },
        name = "Opppo"
    },
      [21] = {
        center  = { x = 1995.1865, y = 2710.6738, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 3600,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1915.1865, y = 2650.6738, z = 10.8203,
            w = 160.0000, h = 120.0000,
            dim = 0,
        },
        name = "IRAQ"
    },
       [22] = {
        center  = { x = 2159.5576, y = 2736.5420, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2097.0576, y = 2706.5420, z = 10.8203,
            w = 125.0000, h = 60.0000,
            dim = 0,
        },
        name = "css"
    },
        [23] = {
        center  = { x = 2317.5322, y = 2773.3447, z = 14.8222 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2237.5322, y = 2723.3447, z = 14.8222,
            w = 160.0000, h = 100.0000,
            dim = 0,
        },
        name = "ALKOL"
    },
        [24] = {
        center  = { x = 2607.8975, y = 2769.4268, z = 19.8232 },
        loyalty = 100,
        gang    = nil,
        money   = 5000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2497.8975, y = 2689.4268, z = 19.8232,
            w = 220.0000, h = 160.0000,
            dim = 0,
        },
        name = "factory"
    },
        [25] = {
        center  = { x = 2592.8311, y = 2277.7051, z = 15.9078 },
        loyalty = 100,
        gang    = nil,
        money   = 1000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2557.8311, y = 2242.7051, z = 15.9078,
            w = 70.0000, h = 70.0000,
            dim = 0,
        },
        name = "d3s"
    },
        [26] = {
        center  = { x = 2848.0625, y = 2355.7949, z = 11.0625 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2798.0625, y = 2305.7949, z = 11.0625,
            w = 100.0000, h = 100.0000,
            dim = 0,
        },
        name = "perfeckt"
    },
       [27] = {
        center  = { x = 2808.3525, y = 2209.1943, z = 10.8232 },
        loyalty = 100,
        gang    = nil,
        money   = 800,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2778.3525, y = 2124.1943, z = 10.8232,
            w = 60.0000, h = 170.0000,
            dim = 0,
        },
        name = "takk"
    },
        [28] = {
        center  = { x = 2598.1182, y = 1834.1758, z = 14.7564 },
        loyalty = 100,
        gang    = nil,
        money   = 4000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2518.1182, y = 1724.1758, z = 14.7564,
            w = 160.0000, h = 220.0000,
            dim = 0,
        },
        name = "rand"
    },
        [29] = {
        center  = { x = 2357.7686, y = 2318.3896, z = 13.4186 },
        loyalty = 100,
        gang    = nil,
        money   = 4000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2297.7686, y = 2243.3896, z = 13.4186,
            w = 120.0000, h = 160.0000,
            dim = 0,
        },
        name = "police"
    },
    [30] = {
        center  = { x = 2431.6553, y = 1662.6025, z = 19.3468 },
        loyalty = 100,
        gang    = nil,
        money   = 1500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2336.6553, y = 1622.6025, z = 19.3468,
            w = 190.0000, h = 80.0000,
            dim = 0,
        },
        name = "old"
    },
      [31] = {
        center  = { x = 2308.0518, y = 1451.7529, z = 49.5789 },
        loyalty = 100,
        gang    = nil,
        money   = 5000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2255.5518, y = 1381.7529, z = 49.5789,
            w = 105.0000, h = 140.0000,
            dim = 0,
        },
        name = "ip"
    },
        [32] = {
      center  = { x = 2515.2676, y = 1546.2080, z = 10.8272 },
        loyalty = 100,
        gang    = nil,
        money   = 3500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2437.7676, y = 1483.7080, z = 10.8272,
            w = 155.0000, h = 125.0000,
            dim = 0,
        },
        name = "zop"
    },
        [33] = {
        center  = { x = 2483.0449, y = 1423.8232, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 900,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2438.0449, y = 1383.8232, z = 10.8203,
            w = 90.0000, h = 80.0000,
            dim = 0,
        },
        name="RIX"
    },
        [34] = {
        center  = { x = 2522.0215, y = 1198.6641, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 5000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2437.0215, y = 1083.6641, z = 10.8203,
            w = 170.0000, h = 290.0000,
            dim = 0,
        },
        name = "Core"
    },
        [35] = {
        center  = { x = 2493.8662, y = 1016.5430, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 2000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2433.8662, y = 961.5430, z = 10.8203,
            w = 120.0000, h = 110.0000,
            dim = 0,
        },
        name = "kilp"
    },
        [36] = {
        center  = { x = 2242.5752, y = 1283.5732, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 11000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2082.5752, y = 1203.5732, z = 10.8203,
            w = 340.0000, h = 160.0000,
            dim = 0,
        },
        name = "Egypt"
    },
        [37] = {
        center  = { x = 2212.7422, y = 1083.4336, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 7500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2082.7422, y = 983.4336, z = 10.8203,
            w = 260.0000, h = 200.0000,
            dim = 0,
        },
        name = "shcon"
    },
        [38] = {
        center  = { x = 2157.7773, y = 1458.7607, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 5000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2082.7773, y = 1383.7607, z = 10.8203,
            w = 150.0000, h = 145.0000,
            dim = 0,
        },
        name = "-Five"
    },
        [39] = {
        center  = { x = 2215.1582, y = 1651.4404, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 7500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2115.1582, y = 1543.9404, z = 10.8203,
            w = 200.0000, h = 215.0000,
            dim = 0,
        },
        name = "casino"
    },
        [40] = {
        center  = { x = 2221.5801, y = 1833.3740, z = 16.5337 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2161.5801, y = 1783.3740, z = 16.5337,
            w = 120.0000, h = 100.0000,
            dim = 0,
        },
    
        name = "empty"
    },
        [41] = {
        center  = { x = 2251.2373, y = 2082.5068, z = 32.8346 },
        loyalty = 100,
        gang    = nil,
        money   = 2000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2163.7373, y = 2032.5068, z = 32.8346,
            w = 175.0000, h = 100.0000,
            dim = 0,
        },
        name = "nilo"
    },
        [42] = {
        center  = { x = 2247.0547, y = 1958.4756, z = 10.8125 },
        loyalty = 100,
        gang    = nil,
        money   = 2500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2167.0547, y = 1903.4756, z = 10.8125,
            w = 160.0000, h = 110.0000,
            dim = 0,
        },
        name = "zin"
    },
        [43] = {
        center  = { x = 2827.7236, y = 1303.7959, z = 22.3714 },
        loyalty = 100,
        gang    = nil,
        money   = 800,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2797.7236, y = 1223.7959, z = 22.3714,
            w = 60.0000, h = 160.0000,
            dim = 0,
        },
        name = "train"
    },
        [44] = {
        center  = { x = 2834.9746, y = 925.7617, z = 15.2923 },
        loyalty = 100,
        gang    = nil,
        money   = 3400,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2777.4746, y = 833.2617, z = 15.2923,
            w = 115.0000, h = 185.0000,
            dim = 0,
        },
        name = "RUSH"
    },
        [45] = {
        center  = { x = 2598.2461, y = 734.0762, z = 11.0234 },
        loyalty = 100,
        gang    = nil,
        money   = 900,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2518.2461, y = 704.0762, z = 11.0234,
            w = 160.0000, h = 60.0000,
            dim = 0,
        },
        name = "hasad"
    },
        [46] = {
        center  = { x = 2287.3789, y = 695.8682, z = 10.6719 },
        loyalty = 100,
        gang    = nil,
        money   = 4500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2157.3789, y = 633.3682, z = 10.6719,
            w = 260.0000, h = 125.0000,
            dim = 0,
        },
        name = "Omdas"
    },
     [47] = {
        center  = { x = 1926.7998, y = 706.3213, z = 19.3469 },
        loyalty = 100,
        gang    = nil,
        money   = 1350,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1881.7998, y = 651.3213, z = 19.3469,
            w = 90.0000, h = 110.0000,
            dim = 0,
        },
    
        name = "niola"
    },
        [48] = {
        center  = { x = 2070.0332, y = 708.1387, z = 10.8198 },
        loyalty = 100,
        gang    = nil,
        money   = 3000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 2000.0332, y = 633.1387, z = 10.8198,
            w = 140.0000, h = 160.0000,
            dim = 0,
        },
        name ="dira"
    },

        [49] = {
        center  = { x = 1930.3975, y = 993.7373, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 6000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1837.8975, y = 903.7373, z = 10.8203,
            w = 195.0000, h = 180.0000,
            dim = 0,
        },
        name = "ONJ"
    },
     [50] = {
        center  = { x = 1940.1836, y = 1181.8506, z = 16.6315 },
        loyalty = 100,
        gang    = nil,
        money   = 6000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1847.6836, y = 1101.8506, z = 16.6315,
            w = 185.0000, h = 165.0000,
            dim = 0,
        },
        name = "middle"
    },
        [51] = {
        center  = { x = 1932.7568, y = 1363.6758, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 6000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1837.7568, y = 1283.6758, z = 10.8203,
            w = 195.0000, h = 160.0000,
            dim = 0,
        },
        name = "mid 2"
    },
        [52] = {
        center  = { x = 1911.7070, y = 1517.4189, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 3800,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1841.7070, y = 1467.4189, z = 10.8203,
            w = 140.0000, h = 100.0000,
            dim = 0,
        },
        name = "vy"
    },
      [53] = {
        center  = { x = 1980.1875, y = 1939.2520, z = 28.5098 },
        loyalty = 100,
        gang    = nil,
        money   = 4500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1852.6875, y = 1869.2520, z = 28.5098,
            w = 255.0000, h = 140.0000,
            dim = 0,
        },
        name = "OK"
    },
    [54] = {
        center  = { x = 1664.9541, y = 998.2471, z = 27.5752 },
        loyalty = 100,
        gang    = nil,
        money   = 4000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1577.4541, y = 883.2471, z = 27.5752,
            w = 180.0000, h = 240.0000,
            dim = 0,
        },
        name = "Sond"
    },
        [55] = {
        center  = { x = 1707.4717, y = 1203.9805, z = 18.2319 },
        loyalty = 100,
        gang    = nil,
        money   = 1500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1657.4717, y = 1143.9805, z = 18.2319,
            w = 100.0000, h = 120.0000,
            dim = 0,
        },
        name = "try"
    },
       [56] = {
        center  = { x = 1437.5791, y = 1011.7402, z = 25.6432 },
        loyalty = 100,
        gang    = nil,
        money   = 2400,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1377.5791, y = 906.7402, z = 25.6432,
            w = 120.0000, h = 210.0000,
            dim = 0,
        },
        name = "Teleg"
    },
      [57] = {
        center  = { x = 1478.7773, y = 728.4004, z = 20.4876 },
        loyalty = 100,
        gang    = nil,
        money   = 1500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1398.7773, y = 663.4004, z = 20.4876,
            w = 160.0000, h = 135.0000,
            dim = 0,
        },
        name = "gaming"
    },
      [58] = {
        center  = { x = 1376.9414, y = 731.3311, z = 10.8203 },
        loyalty = 100,
        gang    = nil,
        money   = 800,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1357.9414, y = 663.8311, z = 10.8203,
            w = 38.0000, h = 135.0000,
            dim = 0,
        },
        name = "copy"
    },
       [59] = {
        center  = { x = 1665.1465, y = 725.5947, z = 12.1429 },
        loyalty = 100,
        gang    = nil,
        money   = 2000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1577.6465, y = 663.0947, z = 12.1429,
            w = 175.0000, h = 125.0000,
            dim = 0,
        },
        name = "semi final"
    },
     [60] = {
        center  = { x = 1081.1963, y = 1080.9072, z = 48.1328 },
        loyalty = 100,
        gang    = nil,
        money   = 4500,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1006.1963, y = 1005.9072, z = 48.1328,
            w = 150.0000, h = 150.0000,
            dim = 0,
        },
        name = "ix"
    },
        [61] = {
        center  = { x = 1394.5693, y = 2654.0723, z = 16.5096 },
        loyalty = 100,
        gang    = nil,
        money   = 4000,
        color   = { r = 255, g = 255, b = 255 },
        stat    = false,
        position = {
            x = 1259.5693, y = 2599.0723, z = 16.5096,
            w = 270.0000, h = 110.0000,
            dim = 0,
        },
        name = "FFF"
    },

}

-- ================= build map elements =================
local function buildZone(z)
    z.cr, z.cg, z.cb = 255, 255, 255 -- cached HUD gang color (neutral white)
    local p = z.position
    -- colored zone on the map (radar area, visible to everyone)
    z.radar = createRadarArea(p.x, p.y, p.w, p.h, z.color.r, z.color.g, z.color.b, 130)
    -- shape that fires events when someone walks in
    z.col = createColRectangle(p.x, p.y, p.w, p.h)
    if not z.col then return end
    setElementDimension(z.col, p.dim)
    addEventHandler("onColShapeHit", z.col, function(hit, matchingDim)
        if not matchingDim then return end
        -- a vehicle itself is ignored, but its occupants are tracked (on-foot
        -- status is re-checked every tick; drivers never count as capturers)
        if getElementType(hit) == "vehicle" then
            z.inside = z.inside or {}
            for _, occ in pairs(getVehicleOccupants(hit) or {}) do
                if isElement(occ) then z.inside[occ] = true end
            end
            return
        end
        if getElementType(hit) ~= "player" then return end
        -- track occupant for the capture ticks (pruned there if invalid)
        z.inside = z.inside or {}
        z.inside[hit] = true
        -- walking into an ongoing attack: owner members get the blip at once
        if z.stat == true then ensureBlip(z, hit) end
        -- push zone info to the player's HUD (no chat spam, color included)
        triggerClientEvent(hit, "turf:zoneInfo", resourceRoot, zoneInfoTable(z))
    end)
    addEventHandler("onColShapeLeave", z.col, function(hit, matchingDim)
        if not matchingDim then return end
        if getElementType(hit) ~= "player" then return end
        if z.inside then z.inside[hit] = nil end
        triggerClientEvent(hit, "turf:zoneInfo", resourceRoot, false) -- hide HUD
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, z in pairs(zones) do
        buildZone(z)
    end
    -- seed occupants already standing inside (no hit event fires for them)
    for _, z in pairs(zones) do
        if z.col then
            for _, p in ipairs(getElementsByType("player")) do
                if isElement(p) and isElementWithinColShape(p, z.col) then
                    z.inside = z.inside or {}
                    z.inside[p] = true
                end
            end
        end
    end
    outputServerLog("[group_system_v2][turf] zones built: " .. #zones)
end)

-- ================= clan color sync (turf follows color changes) =================
-- Fired by group_server when a clan changes its TURF COLOR: every zone owned
-- by that clan takes the new color immediately (no restart, no recapture).
addEvent("group:clanColorChanged")
addEventHandler("group:clanColorChanged", resourceRoot, function(clanName, r, g, b)
    if type(clanName) ~= "string" then return end
    r, g, b = tonumber(r) or 255, tonumber(g) or 255, tonumber(b) or 255
    for _, z in pairs(zones) do
        if z.gang == clanName then
            z.color = {r = r, g = g, b = b}
            z.cr, z.cg, z.cb = r, g, b -- invalidate HUD color cache
            if z.radar and isElement(z.radar) then
                setRadarAreaColor(z.radar, r, g, b, 130)
            end
        end
    end
end)

-- ================= capture engine (loyalty drain + takeover) =================
-- Every 1s per zone: if exactly ONE clan is eligible inside and the zone is not
-- theirs, loyalty -1. At 0 the zone transfers to that clan (loyalty resets to
-- 100, radar takes the clan color). Two or more clans inside = contested,
-- the drain pauses. Live loyalty is pushed to occupants' HUD every tick.
-- One eligible clan inside drains; ineligible players are fully ignored.
-- Drivers never count, even if their clanmates are capturing on foot.
local function isCaptureEligible(p)
    if isPedInVehicle(p) then return nil end
    local team = getPlayerTeam(p)
    if not team or getTeamName(team) ~= "N/A" then return nil end
    local clan = getElementData(p, "Clan")
    if not clan or clan == "" then return nil end
    if getElementDimension(p) ~= 0 or getElementInterior(p) ~= 0 then return nil end
    return clan
end

-- Full HUD payload from the cached zone color (zero export calls per push).
-- GLOBAL (not local): buildZone above calls it, and Lua only sees locals
-- declared before the caller in source order.
function zoneInfoTable(z)
    return {
        name = z.name, gang = z.gang, loyalty = z.loyalty, money = z.money,
        cr = z.cr or 255, cg = z.cg or 255, cb = z.cb or 255,
    }
end

local function pushZoneInfoTo(players, z)
    local info = zoneInfoTable(z)
    for _, p in ipairs(players) do
        if isElement(p) then
            triggerClientEvent(p, "turf:zoneInfo", resourceRoot, info)
        end
    end
end

local function clanTurfColor(player)
    local res = getResourceFromName("group_system_v2")
    if not res then return 255, 255, 255 end
    local r, g, b = call(res, "getGroupTurfColor", player)
    return tonumber(r) or 255, tonumber(g) or 255, tonumber(b) or 255
end

-- Attack blips (icon 59) for the OWNER clan's online members only.
-- Neutral zones (no gang) show blips to nobody.
-- GLOBAL (not local): called from buildZone's hit handler above.
function ensureBlip(z, p)
    if not z.gang then return end
    if not isElement(p) then return end
    if getElementData(p, "Clan") ~= z.gang then return end
    z.blips = z.blips or {}
    if not z.blips[p] or not isElement(z.blips[p]) then
        local blip = createBlip(z.center.x, z.center.y, z.center.z, 59, 2, 255, 255, 255, 255, 16383.3, p)
        if blip then z.blips[p] = blip end
    end
end

local function attackBlipsOn(z)
    if not z.gang then return end
    for _, p in ipairs(getElementsByType("player")) do
        ensureBlip(z, p)
    end
end

local function attackBlipsOff(z)
    if z.blips then
        for p, b in pairs(z.blips) do
            if isElement(b) then destroyElement(b) end
        end
        z.blips = nil
    end
end

addEventHandler("onPlayerQuit", root, function()
    for _, z in pairs(zones) do
        if z.blips and z.blips[source] then
            if isElement(z.blips[source]) then destroyElement(z.blips[source]) end
            z.blips[source] = nil
        end
    end
end)

-- Login during an ongoing attack: owner members get the blip immediately.
-- (group_server's own onPlayerLogin runs first, so "Clan" data is ready.)
addEventHandler("onPlayerLogin", root, function()
    for _, z in pairs(zones) do
        if z.stat == true and z.gang then
            ensureBlip(z, source)
        end
    end
end)

-- 1s capture ticks: occupants are tracked event-driven (hit/leave) so each
-- tick only touches zones that actually have players inside.
-- Drain pace by same-clan attacker count (1->5s, 2->4s, 3->3.5s, 4+->3s),
-- scheduled by timestamp so fractional paces stay exact.
-- Regen 1/5s while NOBODY eligible is inside (even fully empty zones).
-- HUD pushes to occupants every tick.
setTimer(function()
    local now = getTickCount()
    for _, z in pairs(zones) do
        if z.col then
            -- prune tracked occupants, then classify the eligible clans.
            -- Empty zones skip straight to regen below (n stays 0).
            local occupants, seen, counts, sample = {}, {}, {}, {}
            if z.inside then
                for p in pairs(z.inside) do
                    if isElement(p) and isElementWithinColShape(p, z.col) then
                        table.insert(occupants, p)
                        local c = isCaptureEligible(p)
                        if c then
                            counts[c] = (counts[c] or 0) + 1
                            if not seen[c] then
                                seen[c] = true
                                sample[c] = p
                            end
                        end
                    else
                        z.inside[p] = nil -- quit / teleported / dimension changed
                    end
                end
            end
            local only, n, cnt = nil, 0, 0
            for c in pairs(seen) do n = n + 1; only = c end
            if n == 1 then cnt = counts[only] or 0 end
            -- drain pace by same-clan attacker count: 1->5s, 2->4s, 3->3.5s, 4+->3s
            local paceMs = cnt >= 4 and 3000 or (cnt == 3 and 3500 or (cnt == 2 and 4000 or 5000))
            if n == 1 and z.gang ~= only then
                -- drain, attributed to the single eligible clan
                z.regenTick = 0
                if (z.nextDrainAt or 0) <= now then
                    z.nextDrainAt = now + paceMs
                    z.loyalty = (tonumber(z.loyalty) or 0) - 1
                end
                if z.loyalty <= 0 then
                    z.gang = only
                    z.loyalty = 100
                    local r, g, b = clanTurfColor(sample[only])
                    z.color = {r = r, g = g, b = b}
                    z.cr, z.cg, z.cb = r, g, b -- HUD gang name follows the new color
                    if z.radar and isElement(z.radar) then
                        setRadarAreaColor(z.radar, r, g, b, 130)
                    end
                    outputServerLog("[group_system_v2][turf] '" .. tostring(z.name) .. "' captured by '" .. only .. "'")
                end
            elseif n == 0 and (tonumber(z.loyalty) or 0) < 100 then
                -- no eligible capturers (even fully empty): recover 1 per 5s
                z.nextDrainAt = nil
                z.regenTick = (z.regenTick or 0) + 1
                if z.regenTick >= 5 then
                    z.regenTick = 0
                    z.loyalty = math.min(100, (tonumber(z.loyalty) or 0) + 1)
                end
            else
                z.nextDrainAt = nil
                z.regenTick = 0
            end
            -- stat + radar blink + blips: loyalty at/below 50 means under attack
            local shouldFlash = (tonumber(z.loyalty) or 0) <= 50
            if shouldFlash ~= (z.stat == true) then
                z.stat = shouldFlash
                if z.radar and isElement(z.radar) then
                    setRadarAreaFlashing(z.radar, shouldFlash)
                end
                if shouldFlash then
                    attackBlipsOn(z) -- owner members only; nobody if neutral
                else
                    attackBlipsOff(z)
                end
            end
            if #occupants > 0 then
                -- push on change, plus a 5s heartbeat so late joiners of the
                -- tick stream never stay stale
                z.hbTick = (z.hbTick or 0) + 1
                local lp = z.lastPush
                local curLoy = tonumber(z.loyalty) or 0
                local changed = (not lp)
                    or lp.gang ~= z.gang or lp.loyalty ~= curLoy or lp.money ~= z.money
                    or (lp.cr or 255) ~= (z.cr or 255)
                    or (lp.cg or 255) ~= (z.cg or 255)
                    or (lp.cb or 255) ~= (z.cb or 255)
                if changed or z.hbTick >= 5 then
                    z.hbTick = 0
                    z.lastPush = {gang = z.gang, loyalty = curLoy, money = z.money,
                        cr = z.cr, cg = z.cg, cb = z.cb}
                    pushZoneInfoTo(occupants, z)
                end
            end
        end
    end
end, 1000, 0)

-- ================= turf income (every 60s, owner clan members inside) =================
-- Each owned zone pays its money split equally among the owner clan's ONLINE
-- members standing inside it (e.g. 20000 with 2 inside = 10000 each).
-- Paid via money resource + infoSystem notification per receiver.
setTimer(function()
    local moneyRes = getResourceFromName("money")
    if not moneyRes or getResourceState(moneyRes) ~= "running" then return end
    local infoRes = getResourceFromName("infoSystem")
    local infoOK = infoRes and getResourceState(infoRes) == "running"
    for _, z in pairs(zones) do
        local zmoney = tonumber(z.money) or 0
        if z.gang and zmoney > 0 and z.col and z.inside then
            local members = {}
            for p in pairs(z.inside) do
                if isElement(p) and getElementType(p) == "player"
                    and isElementWithinColShape(p, z.col)
                    and getElementData(p, "Clan") == z.gang then
                    table.insert(members, p)
                end
            end
            local n = #members
            if n > 0 then
                local share = math.floor(zmoney / n)
                if share > 0 then
                    for _, p in ipairs(members) do
                        if isElement(p) and exports.money:addMoney(p, share) then
                            if infoOK then
                                exports.infoSystem:sendOfficialNotificationToPlayer(
                                    p, {90, 220, 140},
                                    "Turf income: +$" .. share .. " from " .. tostring(z.name))
                            end
                        end
                    end
                end
            end
        end
    end
end, 60000, 0)

-- ================= test tool: /area <w> <h> =================
-- Creates a LIVE zone (radar + colshape) whose CORNER 1 is exactly where you
-- stand (same rule as zones[1]), then prints a ready-to-paste zones{} object
-- in your F8 console + server log.
math.randomseed(getTickCount())

local function round4(n) return math.floor(n * 10000 + 0.5) / 10000 end

local function printZoneObject(player, z, id)
    local c, p = z.center, z.position
    local lines = {
        "    [" .. id .. "] = {",
        string.format("        center  = { x = %.4f, y = %.4f, z = %.4f },", c.x, c.y, c.z),
        "        loyalty = " .. z.loyalty .. ",",
        "        gang    = nil,",
        "        money   = " .. z.money .. ",",
        string.format("        color   = { r = %d, g = %d, b = %d },", z.color.r, z.color.g, z.color.b),
        '        stat    = ' .. tostring(z.stat) .. ',',
        "        position = {",
        string.format("            x = %.4f, y = %.4f, z = %.4f,", p.x, p.y, p.z),
        string.format("            w = %.4f, h = %.4f,", p.w, p.h),
        "            dim = " .. (p.dim or 0) .. ",",
        "        },",
        "    },",
    }
    outputConsole("---- copy this into zones {} ----", player)
    for _, line in ipairs(lines) do
        outputConsole(line, player)
        outputServerLog("[group_system_v2][turf] /area " .. line)
    end
end

addCommandHandler("area", function(player, _, w, h)
    w, h = tonumber(w), tonumber(h)
    if not w or not h or w <= 0 or h <= 0 then
        outputConsole("Usage: /area <w> <h>   (e.g. /area 100 50)", player)
        return
    end
    local x, y, z = getElementPosition(player)
    local dim = getElementDimension(player) or 0
    local id = #zones + 1
    local zone = {
        -- middle of the rect, computed from corner 1 (informational only)
        center  = { x = round4(x + w / 2), y = round4(y + h / 2), z = round4(z) },
        loyalty = 100,
        gang    = nil,
        money   = 0,
        color   = { r = 255, g = 255, b = 255 }, -- default white (neutral)
        stat    = false,
        position = {
            -- corner 1 anchor = EXACTLY where you stand (same as zones[1])
            x = round4(x), y = round4(y), z = round4(z),
            w = w, h = h,
            dim = dim,
        },
    }
    zones[id] = zone
    buildZone(zone)
    printZoneObject(player, zone, id)
    outputConsole("Zone #" .. id .. " created (" .. w .. "x" .. h .. ").", player)
end)

