# Copyright (C) 2018  Brodie Gaslam
#
# This file is part of "diffobj - Diffs for R Objects"
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Go to <https://www.r-project.org/Licenses/GPL-2> for a copy of the license.

# borrowed from crayon, will lobby to get it exported

ansi_regex <- paste0("(?:(?:\\x{001b}\\[)|\\x{009b})",
                     "(?:(?:[0-9]{1,3})?(?:(?:;[0-9]{0,3})*)?[A-M|f-m])",
                     "|\\x{001b}[A-M]")

# Function to split a character vector by newlines; handles some special cases

split_new_line <- function(x) {
  y <- x
  y[!nzchar(x)] <- "\n"
  unlist(strsplit(y, "\n"))
}
html_ent_sub <- function(x, style) {
  if(is(style, "StyleHtml") && style@escape.html.entities) {
    x <- gsub("&", "&amp;", x, fixed=TRUE)
    x <- gsub("<", "&lt;", x, fixed=TRUE)
    x <- gsub(">", "&gt;", x, fixed=TRUE)
    x <- gsub("\n", "<br />", x, fixed=TRUE)
    # x <- gsub(" ", "&#32;", x, fixed=TRUE)
  }
  x
}
# Helper function for align_eq; splits up a vector into matched elements and
# interstitial elements, including possibly empty interstitial elements when
# two matches are abutting

align_split <- function(v, m) {
  match.len <- sum(!!m)
  res.len <- match.len * 2L + 1L
  splits <- cumsum(
    c(
      if(length(m)) 1L,
      (!!diff(m) < 0L & !tail(m, -1L)) | (head(m, -1L) & tail(m, -1L))
  ) )
  m.all <- match(m, sort(unique(m[!!m])), nomatch=0L)  # normalize
  m.all[!m.all] <- -ave(m.all, splits, FUN=max)[!m.all]
  m.all[!m.all] <- -match.len - 1L  # trailing zeros
  m.fin <- ifelse(m.all < 0, -m.all * 2 - 1, m.all * 2)
  if(any(diff(m.fin) < 0L))
    stop("Logic Error: non monotonic alignments; contact maintainer") # nocov
  res <- replicate(res.len, character(0L), simplify=FALSE)
  res[unique(m.fin)] <- unname(split(v, m.fin))
  res
}
# Align lists based on equalities on other vectors
#
# The A/B vecs  will be split up into matchd elements, and non-matched elements.
# Each matching element will be surrounding by (possibly empty) non-matching
# elements.
#
# Need to reconcile the padding that happens as a result of alignment as well
# as the padding that happens with atomic vectors

align_eq <- function(A, B, x, context) {
  stopifnot(
    is.integer(A), is.integer(B), !anyNA(c(A, B)),
    is(x, "Diff")
  )
  A.fill <- get_dat(x, A, "fill")
  B.fill <- get_dat(x, B, "fill")
  A.fin <- get_dat(x, A, "fin")
  B.fin <- get_dat(x, B, "fin")

  if(context) {             # Nothing to align if this is context hunk
    A.chunks <- list(A.fin)
    B.chunks <- list(B.fin)
  } else {
    etc <- x@etc
    A.eq <- get_dat(x, A, "eq")
    B.eq <- get_dat(x, B, "eq")

    # Cleanup so only relevant stuff is allowed to match

    A.tok.ratio <- get_dat(x, A, "tok.rat")
    B.tok.ratio <- get_dat(x, B, "tok.rat")

    if(etc@align@count.alnum.only) {
      A.eq.trim <- gsub("[^[:alnum:]]", "", A.eq, perl=TRUE)
      B.eq.trim <- gsub("[^[:alnum:]]", "", B.eq, perl=TRUE)
    } else {
      A.eq.trim <- A.eq
      B.eq.trim <- B.eq
    }
    # TBD whether nchar here should be ansi-aware; probably if in alnum only
    # mode...

    A.valid <- which(
      nchar(A.eq.trim) >= etc@align@min.chars &
      A.tok.ratio >= etc@align@threshold
    )
    B.valid <- which(
      nchar(B.eq.trim) >= etc@align@min.chars &
      B.tok.ratio >= etc@align@threshold
    )
    B.eq.seq <- seq_along(B.eq.trim)

    align <- integer(length(A.eq))
    min.match <- 0L

    # Need to match each element in A.eq to B.eq, though each match consumes the
    # match so we can't use `match`; unfortunately this is slow; for context
    # hunks the match is one to one for each line; also, this whole matching
    # needs to be improved (see issue #37)

    if(length(A.valid) & length(B.valid)) {
      B.max <- length(B.valid)
      B.eq.val <- B.eq.trim[B.valid]

      for(i in A.valid) {
        if(min.match >= B.max) break
        B.match <- which(
          A.eq.trim[[i]] == if(min.match)
            tail(B.eq.val, -min.match) else B.eq.val
        )
        if(length(B.match)) {
          align[[i]] <- B.valid[B.match[[1L]] + min.match]
          min.match <- B.match[[1L]] + min.match
        }
      }
    }
    # Group elements together.  We number the interstitial buckest as the
    # negative of the next match.  There are always matches together, split
    # by possibly empty interstitial elements

    align.b <- seq_along(B.eq)
    align.b[!align.b %in% align] <- 0L
    A.chunks <- align_split(A.fin, align)
    B.chunks <- align_split(B.fin, align.b)
  }
  if(length(A.chunks) != length(B.chunks))
    # nocov start
    stop("Logic Error: aligned chunks unequal length; contact maintainer.")
    # nocov end

  list(A=A.chunks, B=B.chunks, A.fill=A.fill, B.fill=B.fill)
}
# if last char matches, repeat, but only if not in use.ansi mode
#
# needed b/c col_strsplit behaves differently than strisplit when delimiter
# is at end.  Will break if you pass a regex reserved character as pad

pad_end <- function(x, pad, use.ansi) {
  stopifnot(
    is.character(x), !anyNA(x), is.character(pad), length(pad) == 1L,
    !is.na(pad), nchar(pad) == 1L, is.TF(use.ansi)
  )
  if(!use.ansi || packageVersion("crayon") >= "1.3.2")
    sub(paste0(pad, "$"), paste0(pad, pad), x) else x
}
# Calculate how many lines of screen space are taken up by the diff hunks
#
# `disp.width` should be the available display width, this function computes
# the net real estate account for mode, padding, etc.

nlines <- function(txt, disp.width, mode) {
  use.ansi <- crayon::has_color()
  # stopifnot(is.character(txt), all(!is.na(txt)))
  capt.width <- calc_width_pad(disp.width, mode)
  if(use.ansi) txt <- crayon::strip_style(txt)
  pmax(1L, as.integer(ceiling(nchar(txt) / capt.width)))
}
# Gets rid of tabs and carriage returns
#
# Assumes each line is one screen line
# @param stops may be a single positive integer value, or a vector of values
#   whereby the last value will be repeated as many times as necessary

strip_hz_c_int <- function(txt, stops, use.ansi, nc_fun, sub_fun, split_fun) {

  # remove trailing and leading CRs (need to record if trailing remains to add
  # back at end? no, not really since by structure next thing must be a newline

  w.chr <- nzchar(txt)  # corner case with strsplit and zero length strings
  txt <- gsub("^\r+|\r+$", "", txt)
  has.tabs <- grep("\t", txt, fixed=TRUE)
  has.crs <- grep("\r", txt, fixed=TRUE)
  txt.s <- as.list(txt)
  txt.s[has.crs] <- if(!any(has.crs)) list() else split_fun(txt[has.crs], "\r+")

  # Assume \r resets tab stops as it would on a type writer; so now need to
  # generate the set maximum set of possible tab stops; approximate here by
  # using largest stop

  if(length(has.tabs)) {
    max.stop <- max(stops)
    width.w.tabs <- max(
      vapply(
        txt.s[has.tabs], function(x) {
          # add number of chars and number of tabs times max tab length
          sum(
            nc_fun(x) + (
              vapply(strsplit(x, "\t"), length, integer(1L)) +
              grepl("\t$", x) - 1L
            ) * max.stop
          )
        }, integer(1L)
    ) )
    extra.chars <- width.w.tabs - sum(stops)
    extra.stops <- ceiling(extra.chars / tail(stops, 1L))
    stop.vec <- cumsum(c(stops, rep(tail(stops, 1L), extra.stops)))

    # For each line, assess effects of tabs

    txt.s[has.tabs] <- lapply(txt.s[has.tabs],
      function(x) {
        if(length(h.t <- grep("\t", x, fixed=T))) {
          # workaround for strsplit dropping trailing tabs
          x.t <- pad_end(x[h.t], "\t", use.ansi)
          x.s <- split_fun(x.t, "\t")

          # Now cycle through each line with tabs and replace them with
          # spaces

          res <- vapply(x.s,
            function(y) {
              topad <- head(y, -1L)
              rest <- tail(y, 1L)
              chrs <- nc_fun(topad)
              pads <- character(length(topad))
              txt.len <- 0L
              for(i in seq_along(topad)) {
                txt.len <- chrs[i] + txt.len
                tab.stop <- head(which(stop.vec > txt.len), 1L)
                if(!length(tab.stop))
                  # nocov start
                  stop(
                    "Logic Error: failed trying to find tab stop; contact ",
                    "maintainer"
                  )
                  # nocov end
                tab.len <- stop.vec[tab.stop]
                pads[i] <- paste0(rep(" ", tab.len - txt.len), collapse="")
                txt.len <- tab.len
              }
              paste0(paste0(topad, pads, collapse=""), rest)
            },
            character(1L)
          )
          x[h.t] <- res
        }
        x
  } ) }
  # Simulate the effect of \r by collapsing every \r separated element on top
  # of each other with some special handling for ansi escape seqs

  txt.fin <- txt.s
  txt.fin[has.crs] <- vapply(
    txt.s[has.crs],
    function(x) {
      if(length(x) > 1L) {
        chrs <- nc_fun(x)
        max.disp <- c(tail(rev(cummax(rev(chrs))), -1L), 0L)
        res <- paste0(rev(sub_fun(x, max.disp + 1L, chrs)), collapse="")
        # add back every ANSI esc sequence from last line to very end
        # to ensure that we leave in correct ANSI escaped state

        if(use.ansi && grepl(ansi_regex, res, perl=TRUE)) {
          res <- paste0(
            res,
            gsub(paste0(".*", ansi_regex, ".*"), "\\1", tail(x, 1L), perl=TRUE)
        ) }
        res
      } else x
    },
    character(1L)
  )
  # txt.fin should only have one long char vectors as elements
  if(!length(txt.fin)) txt else {
    # handle strsplit corner case where splitting empty string
    txt.fin[!nzchar(txt)] <- ""
    unlist(txt.fin)
  }
}
#' Replace Horizontal Spacing Control Characters
#'
#' Removes tabs, newlines, and carriage returns and manipulates the text so that
#' it looks the renders the same as it did with those horizontal control
#' characters embedded.  This function is used when the
#' \code{convert.hz.white.space} parameter to the
#' \code{\link[=diffPrint]{diff*}} methods is active.  The term \dQuote{strip}
#' is a misnomer that remains for legacy reasons and lazyness.
#'
#' This is an internal function with exposed documentation because it is
#' referenced in an external function's documentation.
#'
#' @keywords internal
#' @param txt character to covert
#' @param stops integer, what tab stops to use

strip_hz_control <- function(txt, stops=8L) {
  # stopifnot(
  #   is.character(txt), !anyNA(txt),
  #   is.integer(stops), length(stops) >= 1L, !anyNA(stops), all(stops > 0L)
  # )

  # for speed in case no special chars, just skip; obviously this adds a penalty
  # for other cases but it is small

  if(!any(grepl("\n|\t|\r", txt, perl=TRUE))) {
    txt
  } else {
    if(length(has.n <- grep("\n", txt, fixed=TRUE))) {
      txt.l <- as.list(txt)
      txt.l.n <- strsplit(txt[has.n], "\n")
      txt.l[has.n] <- txt.l.n
      txt <- unlist(txt.l)
    }
    use.ansi <- crayon::has_color()
    has.ansi <- grepl(ansi_regex, txt, perl=TRUE) & use.ansi
    w.ansi <- which(has.ansi)
    wo.ansi <- which(!has.ansi)

    # since for the time being the crayon funs are a bit slow, only us them on
    # strings that are known to have ansi escape sequences

    res <- character(length(txt))
    res[w.ansi] <- strip_hz_c_int(
      txt[w.ansi], stops, use.ansi, crayon::col_nchar,
      crayon::col_substr, crayon::col_strsplit
    )
    res[wo.ansi] <- strip_hz_c_int(
      txt[wo.ansi], stops, use.ansi, nchar, substr, strsplit
    )
    res
  }
}
# Normalize strings so whitespace differences don't show up as differences

normalize_whitespace <- function(txt) gsub("(\t| )+", " ", trimws(txt))

# Simple text manip functions

chr_trim <- function(text, width) {
  stopifnot(all(width > 2L))
  ifelse(
    nchar(text) > width,
    paste0(substr(text, 1L, width - 2L), ".."),
    text
  )
}
rpad <- function(text, width, pad.chr=" ") {
  use.ansi <- crayon::has_color()
  stopifnot(is.character(pad.chr), length(pad.chr) == 1L, nchar(pad.chr) == 1L)
  nchar_fun <- if(use.ansi) crayon::col_nchar else nchar
  pad.count <- width - nchar_fun(text)
  pad.count[pad.count < 0L] <- 0L
  pad.chrs <- vapply(
    pad.count, function(x) paste0(rep(pad.chr, x), collapse=""), character(1L)
  )
  paste0(text, pad.chrs)
}
# Breaks long character vectors into vectors of length width
#
# Right pads them to full length if requested.  Only attempt to wrap if
# longer than width since wrapping is pretty expensive
#
# Returns a list of split vectors

wrap_int <- function(txt, width, sub_fun, nc_fun) {
  nchars <- nc_fun(txt)
  res <- as.list(txt)
  too.wide <- which(nchars > width)
  res[too.wide] <- lapply(
    too.wide,
    function(i) {
      split.end <- seq(
        from=width, by=width, length.out=ceiling(nchars[[i]] / width)
      )
      split.start <- split.end - width + 1L
      sub_fun(rep(txt[[i]], length(split.start)), split.start, split.end)
  } )
  res
}
wrap <- function(txt, width, pad=FALSE) {
  if(length(grep("\n", txt, fixed=TRUE)))
    # nocov start
    stop("Logic error: wrap input contains newlines; contact maintainer.")
    # nocov end

  # If there are ansi escape sequences, account for them; either way, create
  # a vector of character positions after which we should split our character
  # vector

  use.ansi <- crayon::has_color()
  has.na <- is.na(txt)
  has.chars <- nzchar(txt) & !has.na
  w.chars <- which(has.chars)
  wo.chars <- which(!has.chars & !has.na)

  txt.sub <- txt[has.chars]
  w.ansi.log <- grepl(ansi_regex, txt.sub, perl=TRUE) & use.ansi
  w.ansi <- which(w.ansi.log)
  wo.ansi <- which(!w.ansi.log)

  # Wrap differently depending on whether contains ansi or not, exclude zero
  # length char elements

  res.l <- vector("list", length(txt))
  res.l[has.na] <- NA_character_
  res.l[wo.chars] <- ""
  res.l[w.chars][w.ansi] <-
    wrap_int(txt.sub[w.ansi], width, crayon::col_substr, crayon::col_nchar)
  res.l[w.chars][wo.ansi] <-
    wrap_int(txt.sub[wo.ansi], width, substr, nchar)

  # pad if requested

  if(pad) res.l[!has.na] <- lapply(res.l[!has.na], rpad, width=width)
  res.l
}
