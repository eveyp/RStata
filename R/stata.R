#' Send commands to a Stata process
#'
#' Function that sends commands to a Stata process.
#' @param src character vector of length 1 (path to \code{.do} file) or more (a
#'   set of stata commands). See examples.
#' @param data.in \code{\link{data.frame}} to be passed to Stata
#' @param data.out logical value. If \code{TRUE}, the data at the end of the
#'   Stata command are returned to R.
#' @param stata.path Stata command to be used
#' @param stata.version Version of Stata used
#' @param stata.echo logical value. If \code{TRUE} stata text output will be
#'   printed
#' @param ... parameter passed to \code{\link{write.dta}}
#'
#'   It uses \code{\link[haven]{haven}} (default) or
#'   \code{\link[readstata13]{readstata13}} for Stata version 8 and beyond, and
#'   uses \code{foreign} for Stata version 7 and prior.
#'
#' @param src character vector of length 1 (path to \code{.do} file) or more (a
#'   set of stata commands). See examples.
#' @param data.in \code{\link{data.frame}} to be passed to Stata
#' @param data.out logical value. If \code{TRUE}, the data at the end of the
#'   Stata command are returned to R.
#' @param saveold logical value.If returning data to R and using Stata version
#'   13+, use saveold in Stata to save dataset. Defaults to FALSE.
#' @param package character string. R package to use to read/write Stata
#'   datasets for Stata versions 8 and beyond. can either be \code{"haven"} or
#'   \code{"readstata13"}. defaults to \code{"haven"}.
#' @param stata.path Stata command to be used. Can be supplied in the
#'   environment variable \code{STATA_PATH} or the R option
#'   \code{RStata.StataPath}. The environmental variable is preferred over the R
#'   option.
#' @param stata.version Version of Stata used. Can be supplied in the
#'   environment variable \code{STATA_VERSION} or the R option
#'   \code{RStata.StataVersion}. The environmental variable is preferred over
#'   the R option.
#' @param stata.echo logical value. If \code{TRUE} stata text output will be
#'   printed
#' @param ... parameter passed to \code{\link{write_dta}} or
#'   \code{\link{write.dta}}
#' @examples
#' \dontrun{
#' ## Single command
#' stata("help regress") #<- this won't work in Windows dued to needed
#'                       #   batch mode
#'
#' ## Many commands
#' stata_src <- '
#'
#' version 10
#' set more off
#' sysuse auto
#' reg mpg weight
#'
#' '
#' stata(stata_src)
#'
#' ## External .do file
#' stata("foo.do")
#'
#' ## Data input to Stata
#' x <- data.frame(a = rnorm(3), b = letters[1:3])
#' stata( "sum a", data.in = x)
#'
#' ## Data output from Stata (eg obtain 'auto' dataset)
#' auto <- stata("sysuse auto", data.out = TRUE)
#' head(auto)
#'
#' ## Data input/output
#' (y <- stata("replace a = 2", data.in = x, data.out = TRUE))
#' }
#' @export
stata <- function(
  src = stop("At least 'src' must be specified"),
  data.in = NULL,
  data.out = FALSE,
  saveold = FALSE,
  package = "haven",
  stata.path = NULL,
  stata.version = NULL,
  stata.echo = getOption("RStata.StataEcho", TRUE),
  ...
) {
  ## -------------------------
  ## Data validation and setup
  ## -------------------------
  if (!is.character(src))
    stop("src must be a character")
  
  if (!(is.null(data.in) | is.data.frame(data.in)))
    stop("data.in must be NULL or a data.frame")
  
  if (!is.logical(data.out))
    stop("data.out must be logical")
  
  if (is.null(stata.version)) {
    if (!is.null(getOption("RStata.StataVersion"))) {
      stata.version = getOption("RStata.StataVersion")
    }
    else if (!grepl("\\D", Sys.getenv("STATA_VERSION"))) {
      stata.version = as.integer(Sys.getenv("STATA_VERSION"))
    }
    else {
      stop("You need to specify your Stata version")
    }
  }
  
  if (!is.numeric(stata.version))
    stop("stata.version must be numeric")
  
  if (!is.logical(stata.echo))
    stop("stata.echo must be logical")
  
  if (!package %in% c("haven", "readstata13"))
    stop("package must be either 'haven' or 'readstata13'")
  
  if (is.null(stata.path)) {
    if (!is.null(getOption("RStata.StataPath"))) {
      stata.path = getOption("RStata.StataPath")
    }
    else if (Sys.getenv("STATA_PATH") != "") {
      stata.path = Sys.getenv("STATA_PATH")
    }
    else {
      stop("You need to set up a Stata path; ?chooseStataBin")
    }
  }
  
  OS <- Sys.info()["sysname"]
  OS.type <- .Platform$OS.type
  SRC <- unlist(lapply(src, strsplit, '\n'))
  dataIn <- is.data.frame(data.in)
  dataOut <- data.out[1L]
  stataVersion <- stata.version[1L]
  stataEcho <- stata.echo[1L]
  
  ## -----------------
  ## OS related config
  ## -----------------
  ## in Windows and batch mode a RStata.log (naming after RStata.do
  ## below) is generated in the current directory
  
  if (OS %in% "Windows") {
    winRStataLog <- "RStata.log"
    on.exit(unlink(winRStataLog))
  }
  
  ## -----
  ## Files
  ## -----
  
  ## tempfile could be misleading if the do source other dos 
  ## with relative paths
  doFile <- "RStata.do"
  on.exit(unlink(doFile), add = TRUE)
  
  if (dataIn){
    dtaInFile <- fs::file_temp("RStataDataIn", ext = ".dta")
    if (stataVersion <= 7) {
      foreign::write.dta(
        data.in,
        file = dtaInFile,
        version = 6L,
        ...
      )
    } else {
      package_stata_version = if (stataVersion > 15) 15L else stataVersion
      
      if (package == "haven") {
        haven::write_dta(
          data.in, path = dtaInFile, version = package_stata_version, ...
        )
      }
      
      if (package == "readstata13") {
        readstata13::save.dta13(
          as.data.frame(data.in), file = dtaInFile, version = 13, ...
        )
      }
    }
  }
  
  if (dataOut) {
    dtaOutFile <- fs::file_temp("RStataDataOut", ext = ".dta")
  }
  
  ## -------------------------
  ## Creating the .do file ...
  ## -------------------------
  
  ## External .do script 'support': KIS
  if (file.exists(SRC[1L]))
    SRC <- readLines(SRC[1L])
  
  ## put a placeholder around the part of interest, in order to find
  ## it easily (when removing overhead/setup code for each run)
  cut_me_here <- 'RSTATA: cut me here'
  cut_me_comment <- paste0('/*', cut_me_here, '*/')
  
  ## capture noisily and set cut points
  SRC <- c(
    ifelse(
      dataIn,
      glue::glue("use {dtaInFile}"),
      ''
    ),
    'capture noisily {',
    cut_me_comment,
    SRC,
    cut_me_comment,
    '} /* end capture noisily */'
  )
  
  ## set more off just to be sure nothing will freeze (hopefully :) )
  SRC <- c('set more off', SRC)
 
  if (dataOut) {
    ## put a save or saveold at the end of .do if data.out == TRUE
    save_version = ifelse(stataVersion >= 13 & saveold, "saveold", "save")
    ## for Stata 14, saveold defaults to a Stata 13 dta file
    ## -> use the (Stata 14 only) saveold option: "version(12)" to allow
    ## foreign::read.dta() read compatibility
    save_options = ifelse(stataVersion >= 14 & saveold, ", version(12)", "")
    
    save_cmd = glue::glue('{save_version} "{dtaOutFile}"{save_options}')
    
    SRC <- c(SRC, save_cmd)
  }
  
  ## adding this command to the end simplify life if user make changes but
  ## doesn't want a data.frame back
  SRC <- c(SRC, "exit, clear STATA")
  
  ## -------------
  ## Stata command
  ## -------------
  
  ## ---
  ## IPC
  ## ---
  ## setup the .do file
  ## con <- fifo(doFile, "w+") # <- freeze with fifo in Window
  con <- file(doFile, "w")
  writeLines(SRC, con)
  close(con)
  
  stata_args = doFile
  
  ## With Windows version, /e is almost always needed (if Stata is
  ## installed with GUI)
  if (OS %in% "Windows")
    stata_args = c("/e", stata_args)
  
  on.exit(unlink("stdout.txt"), add = TRUE)
  
  ## execute Stata
  processx::run(
    stata.path,
    args = stata_args,
    echo_cmd = FALSE,
    echo = FALSE,
    stdout = "stdout.txt",
    stderr_to_stdout = TRUE
  )
  stataLog <- readLines("stdout.txt", warn = FALSE)

  if (stataEcho) {
    if (OS %in% "Windows")
      stataLog <- readLines(winRStataLog)
    ## postprocess log, keeping only the output of interest (between rows
    ## having /* RSTATA: cut me here */
    cutpoints <- grep(cut_me_here, stataLog)
    stataLog <- stataLog[seq.int(cutpoints[1] + 1, cutpoints[2] - 1)]
    cat(stataLog, sep = "\n")
  }
  
  ## ------------------
  ## Get data outputted
  ## ------------------
  if (dataOut) {
    if (stataVersion <= 7) {
      res <- foreign::read.dta(dtaOutFile, ...)
    }
    else if (package == "haven") {
      res <- haven::read_dta(dtaOutFile, ...)
    }
    else if (package == "readstata13") {
      res <- readstata13::read.dta13(dtaOutFile, ...)
    }
    
    invisible(res)
  }
}
