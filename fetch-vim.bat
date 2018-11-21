:: fetch-vim.bat: Fetch vim if necessary
:: For use in the editorconfig-core-vimscript Appveyor build

:: If it's already been loaded from the cache, we're done
if exist C:\vim\vim\vim80\vim.exe exit

:: Otherwise, download and unzip it.
appveyor DownloadFile https://github.com/cxw42/editorconfig-core-vimscript/releases/download/v0.1.0/vim.7z

7z x vim.7z -oC:\vim
