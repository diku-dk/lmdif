-- | ignore

import "lmdif"
import "/futlib/random"

module fitter = mk_lmdif f32 xorshift128plus

-- For the test, we will be trying to find polynomial coefficients
-- based on point samples.

let polynomial [d] (coefficients: [d]f32) (variables: [d]f32): f32 =
  iota d
  |> map r32
  |> map2 (**) variables
  |> map2 (*) coefficients
  |> f32.sum

let max_global = 30000
let np = 50

-- We will be generating polynomials whose coefficients are the
-- Fibonacci sequence.  Mostly for fun, but also for easier eyeballing
-- of correctness.
let fibs (n: i32): [n]i32 =
  let mul (x00,x01,x10,x11) (y00,y01,y10,y11)  =
  (x00*y00+x01*y10,
   x00*y01+x01*y11,
   x10*y00+x11*y10,
   x10*y01+x11*y11)
  in scan mul (1,0,0,1) (replicate n (1,1,1,0)) |> map (.2)

-- Used for generating the data set, but not for testing.
entry gen_data [d] (xss: [][d]f32) =
  (xss, map (polynomial (fibs d |> map r32)) xss)

-- ==
-- entry: test_fibs
-- compiled input @ data/fibs7.in.gz
-- output { [1,1,2,3,5,8,13] }
entry test_fibs [d] (xss: [][d]f32) (fs: []f32) =
  let dist coefficients xs f =
    f32.abs (polynomial coefficients xs - f)
  let rms = map (**2) >-> f32.sum >-> (/r32 d) >-> f32.sqrt
  let objective coefficients =
    rms (map2 (dist coefficients) xss fs)
  let var = fitter.optimize_value { lower_bound = -10
                                  , upper_bound = 10
                                  , initial_value = 0 }
  let vars = replicate d var
  let r = fitter.lmdif objective max_global np vars
  in map (f32.round >-> t32) r.parameters
