# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.


#' @include expression.R
NULL


#' Register compute bindings
#'
#' The `register_binding()` and `register_binding_agg()` functions
#' are used to populate a list of functions that operate on (and return)
#' Expressions. These are the basis for the `.data` mask inside dplyr methods.
#'
#' @section Writing bindings:
#' When to use `build_expr()` vs. `Expression$create()`?
#'
#' Use `build_expr()` if you need to
#' - map R function names to Arrow C++ functions
#' - wrap R inputs (vectors) as Array/Scalar
#'
#' `Expression$create()` is lower level. Most of the bindings use it
#' because they manage the preparation of the user-provided inputs
#' and don't need or don't want to the automatic conversion of R objects
#' to [Scalar].
#'
#' @param fun_name A string containing a function name in the form `"function"` or
#'   `"package::function"`. The package name is currently not used but
#'   may be used in the future to allow these types of function calls.
#' @param fun A function or `NULL` to un-register a previous function.
#'   This function must accept `Expression` objects as arguments and return
#'   `Expression` objects instead of regular R objects.
#' @param agg_fun An aggregate function or `NULL` to un-register a previous
#'   aggregate function. This function must accept `Expression` objects as
#'   arguments and return a `list()` with components:
#'   - `fun`: string function name
#'   - `data`: `Expression` (these are all currently a single field)
#'   - `options`: list of function options, as passed to call_function
#' @param registry An environment in which the functions should be
#'   assigned.
#'
#' @return The previously registered binding or `NULL` if no previously
#'   registered function existed.
#' @keywords internal
#'
register_binding <- function(fun_name, fun, registry = nse_funcs) {
  name <- gsub("^.*?::", "", fun_name)
  namespace <- gsub("::.*$", "", fun_name)

  previous_fun <- if (name %in% names(registry)) registry[[name]] else NULL

  if (is.null(fun) && !is.null(previous_fun)) {
    rm(list = name, envir = registry, inherits = FALSE)
  } else {
    registry[[name]] <- fun
  }

  invisible(previous_fun)
}

register_binding_agg <- function(fun_name, agg_fun, registry = agg_funcs) {
  register_binding(fun_name, agg_fun, registry = registry)
}

# Supports functions and tests that call previously-defined bindings
call_binding <- function(fun_name, ...) {
  nse_funcs[[fun_name]](...)
}

call_binding_agg <- function(fun_name, ...) {
  agg_funcs[[fun_name]](...)
}

# Called in .onLoad()
create_binding_cache <- function() {
  arrow_funcs <- list()

  # Register all available Arrow Compute functions, namespaced as arrow_fun.
  if (arrow_available()) {
    all_arrow_funs <- list_compute_functions()
    arrow_funcs <- set_names(
      lapply(all_arrow_funs, function(fun) {
        force(fun)
        function(...) build_expr(fun, ...)
      }),
      paste0("arrow_", all_arrow_funs)
    )
  }

  # Register bindings into nse_funcs and agg_funcs
  register_bindings_array_function_map()
  register_bindings_aggregate()
  register_bindings_conditional()
  register_bindings_datetime()
  register_bindings_duration()
  register_bindings_math()
  register_bindings_string()
  register_bindings_type()

  # We only create the cache for nse_funcs and not agg_funcs
  .cache$functions <- c(as.list(nse_funcs), arrow_funcs)
}

# environments in the arrow namespace used in the above functions
nse_funcs <- new.env(parent = emptyenv())
agg_funcs <- new.env(parent = emptyenv())
.cache <- new.env(parent = emptyenv())
