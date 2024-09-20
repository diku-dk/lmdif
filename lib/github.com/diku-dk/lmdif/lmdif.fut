-- | Nonlinear parameter fitting using the
-- Levenberg-Marquardt-algorithm (sort of a genetic algorithm).
--
-- The `mk_lmdif`@term module is the entry point, which must
-- be given a representation of scalars (which also doubles as the
-- type of parameters) and a way to produce random numbers.

import "../cpprandom/random"

-- | The type of an instantiated `mk_lmdif` module.
module type lmdif = {
  -- | The representation of real numbers.
  type real

  -- | A range for an optimizable varible.  Inclusive lower and upper
  -- bounds, as well as an initial value.
  type range = {lower_bound: real,
                upper_bound: real,
                initial_value: real}

  -- | The result of calibration, which includes the best observed
  -- parameter assignment, its error, and the number of evaluations of
  -- the objective function that was carried out before finding this
  -- result.  The error is simply the value returned by the objective
  -- function for the parameters, and produced here only for
  -- convenience.
  type calibration_result [num_vars] = { parameters: [num_vars]real,
                                         error: real,
                                         num_feval: i32 }

  -- | An input variable to the objective function.  It can be either
  -- fixed or subject to optimization.
  type optimization_variable

  val fixed_value: real -> optimization_variable
  val optimize_value: range -> optimization_variable

  -- | Perform parameter fitting.  `objective` is the objective
  -- function, `max_global` is the maximum number of calls to the
  -- objective function before termination.  `np` is the number of
  -- mutations to attempt per iteration.
  val lmdif [num_vars]:
          [num_vars]optimization_variable
       -> (objective: [num_vars]real -> real)
       -> (max_global: i32) -> (np: i32)
       -> calibration_result [num_vars]
}

module mk_lmdif (real: real)
                (rand: rng_engine)
              : lmdif with real = real.t = {
  type real = real.t

  type range = {lower_bound: real,
                upper_bound: real,
                initial_value: real}

  type calibration_result [num_vars] = { parameters: [num_vars]real,
                                         error: real,
                                         num_feval: i32 }

  -- Pretend this is a sum type with two constructors.
  type optimization_variable = ( #fixed | #not_fixed -- fixed?
                               , real -- value if fixed
                               , range -- range if not fixed
                               )

  module random_i32 = uniform_int_distribution i32 rand
  module random_real = uniform_real_distribution real rand

  let nrand (d: random_real.distribution) (rng: rand.rng) (n: i64) =
    let rngs = rand.split_rng n rng
    let (rngs', xs) = unzip (map (\rng -> random_real.rand d rng) rngs)
    in (rand.join_rng rngs', xs)

  let fixed_value (v: real): optimization_variable =
    (#fixed, v, {lower_bound=real.i32 0,
                 upper_bound=real.i32 0,
                 initial_value=real.i32 0})

  let optimize_value (r: range): optimization_variable =
    (#not_fixed, real.i32 0, r)

  -- Parameterisation of how the randomised search takes place.
  type mutation = {np: i64, -- Population size
                   cr: real  -- Crossover probability [0,1]
                   }

  type termination = {max_iterations: i32, max_global: i32, target: real}

  type status = i32 -- Pretend it's opaque!
  let max_iterations_reached: status = 0
  let max_global_reached: status = 1
  let target_reached: status = 2

  type result [n] = {x0: [n]real, f: real, num_feval: i32, status: status}

  let active_vars [num_vars] [num_active]
                  (vars_to_free_vars: [num_vars]i32)
                  (variables: [num_vars]optimization_variable)
                  (xs: [num_active]real) =
    map2 (\fv (fixed,x,_) -> match fixed
                               case #fixed -> x
                               case #not_fixed -> xs[fv])
         vars_to_free_vars variables

  let min_and_idx (a:real,a_i:i32) (b:real,b_i:i32) =
    if      real.(a < b)    then (a,a_i)
    else if real.(b < a)    then (b,b_i)
    else if i32.(a_i < b_i) then (a, a_i)
    else                         (b, b_i)

  let optimize [num_vars] [num_free_vars]
               (objective: []real -> real)
               (vars_to_free_vars: [num_vars]i32)
               (variables: [num_vars]optimization_variable)
               ({np, cr}: mutation)
               (lower_bounds: [num_free_vars]real)
               (upper_bounds: [num_free_vars]real)
               ({max_iterations,max_global,target}: termination): result [num_free_vars] =
    -- The objective function called only with free variables.
    let objective' x = objective (active_vars vars_to_free_vars variables x)

    let bounds = (real.i32 0, real.i32 1)
    let rng = rand.rng_from_seed [0x123]
    let rngs = rand.split_rng np rng
    let (rngs, rss) = unzip (map (\rng -> nrand bounds rng num_free_vars) rngs)
    let rng = rngs[0]
    let x = (let init_j (lower_bound: real) (upper_bound: real) (r: real) =
               real.(lower_bound + (upper_bound-lower_bound) * r)
             let init_i (rs: [num_free_vars]real) = map3 init_j lower_bounds upper_bounds rs
             in map init_i rss)
    let fx = map objective' x
    let (fx0, best_idx) =
      reduce_comm min_and_idx (real.inf, 0)
                  (zip (opaque fx) (map i32.i64 (iota np)))

    let mutation (difw: real) (best_idx: i32) (x: [np][num_free_vars]real)
                 (rng: rand.rng) (i :i32) (x_i: [num_free_vars]real) =
      (-- We have to draw 'to_draw' distinct elements from 'x', and it
       -- can't be 'i'.  We do this with brute-force looping.
       let dist = (0,i32.i64 np-1)
       let (rng,a) = random_i32.rand dist rng
       let (rng,b) = random_i32.rand dist rng
       let (rng,c) = random_i32.rand dist rng
       let (rng,a) = loop (rng,a) while a i32.== i do random_i32.rand dist rng
       let (rng,b) = loop (rng,b) while b i32.== i || b i32.== a do random_i32.rand dist rng
       let (rng,c) = loop (rng,c) while c i32.== i || c i32.== a || c i32.== b do random_i32.rand dist rng
       let (rng,r) = random_real.rand bounds rng
       let x_r1 = real.(if r <= from_fraction 1 2 then x[best_idx] else x[a])
       let x_r2 = x[b]
       let x_r3 = x[c]
       let (rng,j0) = random_i32.rand (0,i32.i64 num_free_vars-1) rng
       let (rng,rs) = nrand bounds rng num_free_vars
       let auxs = real.(map2 (+) x_r1 (map (difw*) (map2 (-) x_r2 x_r3)))
       let bounds = zip lower_bounds upper_bounds
       let v_i = map5 (\j r (lower_bound, upper_bound) aux x_i_j ->
                       if i32.(j == j0) || real.(r <= cr && lower_bound <= aux && aux <= upper_bound)
                       then aux
                       else x_i_j)
                      (map i32.i64 (iota num_free_vars)) rs bounds auxs x_i

       in (rng, v_i))

    let recombination (fx0: real) (best_idx: i32) (fx: [np]real)
                      (x: [np][num_free_vars]real) (v: [np][num_free_vars]real) =
      (let f_v = map objective' v
       let fx' = map2 real.min f_v fx
       let x' = map4 (\f fx_i x_i v_i -> real.(if f < fx_i then v_i else x_i))
                     f_v fx x v
       let (fx0', best_idx') =
         reduce_comm min_and_idx
                    (fx0, best_idx)
                    (zip (opaque f_v) (map i32.i64 (iota np)))
       in (fx0', best_idx', fx', x'))

    -- We perform np invocations of the objective function per
    -- iteration of the loop.
    let (_,ncalls,num_it,(_,_,_,x)) =
      loop (rng, ncalls, num_it, (fx0, best_idx, fx, x)) =
           (rng, i32.i64 np, max_iterations, (fx0, best_idx, fx, x))
      while i32.(num_it > 0) && i32.(max_global > ncalls) && real.(fx0 > target) do
      (let (rng,differential_weight) = random_real.rand (real.from_fraction 1 2, real.i32 1) rng
       let rngs = rand.split_rng np rng
       let (rngs, v) = unzip (map3 (mutation differential_weight best_idx x)
                                   rngs
                                   (map i32.i64 (iota np))
                                   x)
       let rng = rngs[0]
       let (fx0, best_idx, fx, x) = recombination fx0 best_idx fx x v
       in (rng, ncalls i32.+ i32.i64 np, num_it i32.- 1,
           (fx0, best_idx, fx, x)))
    let x0 = x[best_idx]
    let status = if      real.(fx0 <= target)      then target_reached
                 else if i32.(max_global < ncalls) then max_global_reached
                 else if i32.(num_it == 0)         then max_iterations_reached
                 else 1337 -- never reached
    in {x0=x0, f=fx0, num_feval=ncalls, status=status}

  let lmdif [num_vars]
      (variables: [num_vars]optimization_variable)
      (objective: []real -> real)
      (max_global: i32)
      (np: i32)
      : calibration_result [num_vars] =
    let not_fixed x = match x case #not_fixed -> true
                              case _ -> false
    let (free_vars_to_vars, free_vars) =
      unzip (filter ((.1) >-> (.0) >-> not_fixed) (zip (iota num_vars) variables))
    let num_free_vars = length free_vars
    let vars_to_free_vars = scatter (replicate num_vars (-1))
                                    (free_vars_to_vars :> [num_free_vars]i64)
                                    (map i32.i64 (iota num_free_vars))
    let (x, lower_bounds, upper_bounds) =
      unzip3 (map (\(_, _, {initial_value, lower_bound, upper_bound}) ->
                   (initial_value, lower_bound, upper_bound)) free_vars)

    let (x, num_feval) =
      if max_global i32.> 0
      then let res = (optimize objective vars_to_free_vars variables
                      {np = i64.i32 np, cr = real.from_fraction 9 10} lower_bounds upper_bounds
                      {max_iterations = i32.highest,
                       max_global = max_global,
                       target = real.i32 0})
           in (res.x0, res.num_feval)
      else (x, 0)

    let err = objective (active_vars vars_to_free_vars variables x)

    in {parameters = active_vars vars_to_free_vars variables x,
        error = err,
        num_feval = num_feval}
}
