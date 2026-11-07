{-# LANGUAGE OverloadedStrings #-}
-- | Helpers for the nvim notebooks. Installed with `cabal install --lib`
-- (see README in this folder) and imported from ~/.ghci, so it survives
-- ghci resets like `:set -package` or `:load`.
--
-- Each helper prints a marker line that nvim turns into an inline image:
--   [plot] <spec.vl.json>        rendered with vl-convert
--   [html] <file.html> <stamp>   screenshotted with headless chromium
module Hasknote (showPlot, showHtml, showPlotly, showPlotlyWith) where

import qualified Data.Aeson as Aeson
import Data.Time.Clock.POSIX (getPOSIXTime)
import Graphics.Plotly (Plotly, Trace, plotly)
import Graphics.Plotly.Lucid (plotlyCDN)
import Graphics.Vega.VegaLite (VegaLite, fromVL)
import Lucid (body_, doctypehtml_, head_, renderToFile, toHtml)
import System.Directory (createDirectoryIfMissing, getHomeDirectory, makeAbsolute)

-- | Fresh path in the plot cache, unique per call.
cachePath :: String -> IO FilePath
cachePath ext = do
  home <- getHomeDirectory
  t <- getPOSIXTime
  let dir = home ++ "/.cache/hasknote/plots"
  createDirectoryIfMissing True dir
  return (dir ++ "/" ++ show (round (t * 1000) :: Integer) ++ ext)

-- | Show a hvega chart inline under the cell.
showPlot :: VegaLite -> IO ()
showPlot v = do
  path <- cachePath ".vl.json"
  Aeson.encodeFile path (fromVL v)
  putStrLn ("[plot] " ++ path)

-- | Show any HTML file (plotly, hvega's toHtmlFile, ...) inline under the cell.
showHtml :: FilePath -> IO ()
showHtml file = do
  abs' <- makeAbsolute file
  t <- getPOSIXTime
  putStrLn ("[html] " ++ abs' ++ " " ++ show (round (t * 1000) :: Integer))

-- | Show plotly traces inline: showPlotly [line (aes & x .~ fst & y .~ snd) pts]
showPlotly :: [Trace] -> IO ()
showPlotly traces = showPlotlyWith (plotly "plot" traces)

-- | Like 'showPlotly', for a chart with a custom layout (plotly ... & layout ...).
showPlotlyWith :: Plotly -> IO ()
showPlotlyWith p = do
  path <- cachePath ".html"
  renderToFile path $ doctypehtml_ $ do
    head_ plotlyCDN
    body_ (toHtml p)
  showHtml path
