" ============================================================================
" File:        git_status.vim
" Description: plugin for NERD Tree that provides git status support
" Maintainer:  Xuyuan Pang <xuyuanp at gmail dot com>
" Last Change: 4 Apr 2014
" License:     This program is free software. It comes without any warranty,
"              to the extent permitted by applicable law. You can redistribute
"              it and/or modify it under the terms of the Do What The Fuck You
"              Want To Public License, Version 2, as published by Sam Hocevar.
"              See http://sam.zoy.org/wtfpl/COPYING for more details.
" ============================================================================
if !executable('git')
    finish
endif

if exists('g:loaded_nerdtree_git_status')
    finish
endif
let g:loaded_nerdtree_git_status = 1

if !exists('g:NERDTreeShowGitStatus')
    let g:NERDTreeShowGitStatus = 1
endif

if g:NERDTreeShowGitStatus == 0
    finish
endif

if !exists('g:NERDTreeMapNextHunk')
    let g:NERDTreeMapNextHunk = ']c'
endif

if !exists('g:NERDTreeMapPrevHunk')
    let g:NERDTreeMapPrevHunk = '[c'
endif

if !exists('g:NERDTreeUpdateOnWrite')
    let g:NERDTreeUpdateOnWrite = 1
endif

if !exists('g:NERDTreeUpdateOnCursorHold')
    let g:NERDTreeUpdateOnCursorHold = 1
endif

if !exists('g:NERDTreeShowIgnoredStatus')
    let g:NERDTreeShowIgnoredStatus = 0
endif

if !exists('s:NERDTreeIndicatorMap')
    let s:NERDTreeIndicatorMap = {
                \ 'Modified'  : '✹',
                \ 'Staged'    : '✚',
                \ 'Untracked' : '✭',
                \ 'Renamed'   : '➜',
                \ 'Unmerged'  : '═',
                \ 'Deleted'   : '✖',
                \ 'Dirty'     : '✗',
                \ 'Clean'     : '✔︎',
                \ 'Ignored'   : '☒',
                \ 'Unknown'   : '?'
                \ }
endif

function! s:get_git_version() abort
    let l:output = systemlist('git --version')[0]
    let l:version = split(l:output[12:], '\.')
    let l:major = l:version[0]
    let l:minor = l:version[1]
    return [major, minor]
endfunction

function! s:choose_porcelain_version(git_version) abort
    " git status supports --porcelain=v2 since v2.11.0
    let [major, minor] = a:git_version
    if major < 2
        return 'v1'
    elseif minor < 11
        return 'v1'
    endif
    return 'v2'
endfunction

function! s:process_line_v1(sline)
    let l:pathStr = a:sline[3:]
    let l:statusKey = s:NERDTreeGetFileGitStatusKey(a:sline[0], a:sline[1])
    return [l:pathStr, l:statusKey]
endfunction

function! s:process_line_v2(sline)
        if a:sline[0] ==# '1'
            let l:statusKey = s:NERDTreeGetFileGitStatusKeyV2(a:sline[2], a:sline[3])
            let l:pathStr = a:sline[113:]
        elseif a:sline[0] ==# '2'
            let l:statusKey = 'Renamed'
            let l:pathStr = a:sline[113:]
            let l:pathStr = l:pathStr[stridx(l:pathStr, ' ')+1:]
        elseif a:sline[0] ==# 'u'
            let l:statusKey = 'Unmerged'
            let l:pathStr = a:sline[161:]
        elseif a:sline[0] ==# '?'
            let l:statusKey = 'Untracked'
            let l:pathStr = a:sline[2:]
        elseif a:sline[0] ==# '!'
            let l:statusKey = 'Ignored'
            let l:pathStr = a:sline[2:]
        else
            throw '[nerdtree_git_status] unknown status'
        endif
        return [l:pathStr, l:statusKey]
endfunction


let s:porcelainVersion = s:choose_porcelain_version(s:get_git_version())
let s:process_line = function('s:process_line_' . s:porcelainVersion)

function! NERDTreeGitStatusRefreshListener(event)
    if !exists('b:NOT_A_GIT_REPOSITORY')
        call g:NERDTreeGitStatusRefresh()
    endif
    let l:path = a:event.subject
    let l:flag = g:NERDTreeGetGitStatusPrefix(l:path)
    call l:path.flagSet.clearFlags('git')
    if l:flag !=# ''
        call l:path.flagSet.addFlag('git', l:flag)
    endif
endfunction

function! s:git_workdir()
    let l:output = systemlist('git rev-parse --show-toplevel')
    if len(l:output) > 0 && l:output[0] !~# 'fatal:.*'
        return l:output[0]
    endif
    return ''
endfunction

" FUNCTION: g:NERDTreeGitStatusRefresh() {{{2
" refresh cached git status
function! g:NERDTreeGitStatusRefresh() abort
    let b:NERDTreeCachedGitFileStatus = {}
    let b:NERDTreeCachedGitDirtyDir   = {}
    let b:NOT_A_GIT_REPOSITORY        = 1

    let l:workdir = s:git_workdir()
    if l:workdir ==# ''
        return
    endif

    let l:git_args = [
                \ 'git',
                \ 'status',
                \ '--porcelain' . (s:porcelainVersion ==# 'v2' ? '=v2' : ''),
                \ '--untracked-files=normal',
                \ '-z'
                \ ]
    if g:NERDTreeShowIgnoredStatus
        let l:git_args = l:git_args + ['--ignored=traditional']
    endif
    if exists('g:NERDTreeGitStatusIgnoreSubmodules')
        let l:ignore_args = '--ignore-submodules'
        if g:NERDTreeGitStatusIgnoreSubmodules ==# 'all' ||
                    \ g:NERDTreeGitStatusIgnoreSubmodules ==# 'dirty' ||
                    \ g:NERDTreeGitStatusIgnoreSubmodules ==# 'untracked' ||
                    \ g:NERDTreeGitStatusIgnoreSubmodules ==# 'none'
            let l:ignore_args += '=' . g:NERDTreeGitStatusIgnoreSubmodules
        endif
        let l:git_args += [l:ignore_args]
    endif
    let l:git_cmd = join(l:git_args, ' ')
    " When the -z option is given, pathnames are printed as is and without any quoting and lines are terminated with a NUL (ASCII 0x00, <C-A> in vim) byte. See `man git-status`
    let l:statusLines = split(system(l:git_cmd), "\<C-A>")

    if l:statusLines != [] && l:statusLines[0] =~# 'fatal:.*'
        return
    endif
    let b:NOT_A_GIT_REPOSITORY = 0

    let l:is_rename = v:false
    for l:statusLine in l:statusLines
        " cache git status of files
        if l:is_rename
            call s:NERDTreeCacheDirtyDir(l:workdir, l:workdir . '/' . l:statusLine)
            let l:is_rename = v:false
            continue
        endif
        let [l:pathStr, l:statusKey] = s:process_line(l:statusLine)

        let l:pathStr = l:workdir . '/' . l:pathStr
        let l:is_rename = l:statusKey ==# 'Renamed'
        let b:NERDTreeCachedGitFileStatus[l:pathStr] = l:statusKey

        if l:statusKey == 'Ignored'
            if isdirectory(l:pathStr)
                let b:NERDTreeCachedGitDirtyDir[l:pathStr] = l:statusKey
            endif
        else
            call s:NERDTreeCacheDirtyDir(l:workdir, l:pathStr)
        endif
    endfor
endfunction

function! s:NERDTreeCacheDirtyDir(root, pathStr)
    " cache dirty dir
    let l:dirtyPath = fnamemodify(a:pathStr, ':p:h')
    while l:dirtyPath !=# a:root && has_key(b:NERDTreeCachedGitDirtyDir, l:dirtyPath) == 0
        let b:NERDTreeCachedGitDirtyDir[l:dirtyPath] = 'Dirty'
        let l:dirtyPath = fnamemodify(l:dirtyPath, ':h')
    endwhile
endfunction

" FUNCTION: g:NERDTreeGetGitStatusPrefix(path) {{{2
" return the indicator of the path
" Args: path
let s:GitStatusCacheTimeExpiry = 2
let s:GitStatusCacheTime = 0
function! g:NERDTreeGetGitStatusPrefix(path)
    if localtime() - s:GitStatusCacheTime > s:GitStatusCacheTimeExpiry
        call g:NERDTreeGitStatusRefresh()
        let s:GitStatusCacheTime = localtime()
    endif
    let l:pathStr = a:path.str()
    if a:path.isDirectory
        let l:statusKey = get(b:NERDTreeCachedGitFileStatus, l:pathStr . '/', '')
        if l:statusKey ==# ''
            let l:statusKey = get(b:NERDTreeCachedGitDirtyDir, l:pathStr, '')
        endif
    else
        let l:statusKey = get(b:NERDTreeCachedGitFileStatus, l:pathStr, '')
    endif
    if l:statusKey ==# ''
        return ''
    endif
    return s:NERDTreeGetIndicator(l:statusKey)
endfunction

function! s:NERDTreeGetIndicator(statusKey)
    if exists('g:NERDTreeIndicatorMapCustom')
        let l:indicator = get(g:NERDTreeIndicatorMapCustom, a:statusKey, '')
        if l:indicator !=# ''
            return l:indicator
        endif
    endif
    let l:indicator = get(s:NERDTreeIndicatorMap, a:statusKey, '')
    if l:indicator !=# ''
        return l:indicator
    endif
    return ''
endfunction

function! s:NERDTreeGetFileGitStatusKeyV2(us, them)
    if a:us ==# '.' && a:them ==# 'M'
        return 'Modified'
    elseif a:us =~# '[MAC]'
        return 'Staged'
    elseif a:them ==# 'D'
        return 'Deleted'
    else
        return 'Unknown'
    endif
endfunction

function! s:NERDTreeGetFileGitStatusKey(us, them)
    if a:us ==# '?' && a:them ==# '?'
        return 'Untracked'
    elseif a:us ==# ' ' && a:them ==# 'M'
        return 'Modified'
    elseif a:us =~# '[MAC]'
        return 'Staged'
    elseif a:us ==# 'R'
        return 'Renamed'
    elseif (a:us ==# 'U' && a:them ==# 'U') || (a:us ==# 'A' && a:them ==# 'A') || (a:us ==# 'D' && a:them ==# 'D')
        return 'Unmerged'
    elseif a:them ==# 'D'
        return 'Deleted'
    elseif a:us ==# '!'
        return 'Ignored'
    else
        return 'Unknown'
    endif
endfunction

" FUNCTION: s:jumpToNextHunk(node) {{{2
function! s:jumpToNextHunk(node)
    let l:position = search('\[[^{RO} ].*\]', '')
    if l:position
        call nerdtree#echo('Jump to next hunk')
    endif
endfunction

" FUNCTION: s:jumpToPrevHunk(node) {{{2
function! s:jumpToPrevHunk(node)
    let l:position = search('\[[^{RO} ].*\]', 'b')
    if l:position
        call nerdtree#echo('Jump to prev hunk')
    endif
endfunction

" Function: s:SID()   {{{2
function s:SID()
    if !exists('s:sid')
        let s:sid = matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
    endif
    return s:sid
endfun

" FUNCTION: s:NERDTreeGitStatusKeyMapping {{{2
function! s:NERDTreeGitStatusKeyMapping()
    let l:s = '<SNR>' . s:SID() . '_'

    call NERDTreeAddKeyMap({
        \ 'key': g:NERDTreeMapNextHunk,
        \ 'scope': 'Node',
        \ 'callback': l:s.'jumpToNextHunk',
        \ 'quickhelpText': 'Jump to next git hunk' })

    call NERDTreeAddKeyMap({
        \ 'key': g:NERDTreeMapPrevHunk,
        \ 'scope': 'Node',
        \ 'callback': l:s.'jumpToPrevHunk',
        \ 'quickhelpText': 'Jump to prev git hunk' })

endfunction

augroup nerdtreegitplugin
    autocmd CursorHold * silent! call s:CursorHoldUpdate()
augroup END
" FUNCTION: s:CursorHoldUpdate() {{{2
function! s:CursorHoldUpdate()
    if g:NERDTreeUpdateOnCursorHold != 1
        return
    endif

    if !g:NERDTree.IsOpen()
        return
    endif

    " Do not update when a special buffer is selected
    if !empty(&l:buftype)
        return
    endif

    let l:winnr = winnr()
    let l:altwinnr = winnr('#')

    call g:NERDTree.CursorToTreeWin()
    call b:NERDTree.root.refreshFlags()
    call NERDTreeRender()

    exec l:altwinnr . 'wincmd w'
    exec l:winnr . 'wincmd w'
endfunction

augroup nerdtreegitplugin
    autocmd!
    autocmd BufWritePost * call s:FileUpdate(expand('%:p'))
augroup END
" FUNCTION: s:FileUpdate(fname) {{{2
function! s:FileUpdate(fname)
    if g:NERDTreeUpdateOnWrite != 1
        return
    endif

    if !g:NERDTree.IsOpen()
        return
    endif

    let l:winnr = winnr()
    let l:altwinnr = winnr('#')

    call g:NERDTree.CursorToTreeWin()
    let l:node = b:NERDTree.root.findNode(g:NERDTreePath.New(a:fname))
    if l:node != {}
        call l:node.refreshFlags()
        let l:node = l:node.parent
        while !empty(l:node)
            call l:node.refreshDirFlags()
            let l:node = l:node.parent
        endwhile
        call NERDTreeRender()
    endif

    exec l:altwinnr . 'wincmd w'
    exec l:winnr . 'wincmd w'
endfunction

augroup AddHighlighting
    autocmd FileType nerdtree call s:AddHighlighting()
augroup END
function! s:AddHighlighting()
    let l:synmap = {
                \ 'NERDTreeGitStatusModified'    : s:NERDTreeGetIndicator('Modified'),
                \ 'NERDTreeGitStatusStaged'      : s:NERDTreeGetIndicator('Staged'),
                \ 'NERDTreeGitStatusUntracked'   : s:NERDTreeGetIndicator('Untracked'),
                \ 'NERDTreeGitStatusRenamed'     : s:NERDTreeGetIndicator('Renamed'),
                \ 'NERDTreeGitStatusIgnored'     : s:NERDTreeGetIndicator('Ignored'),
                \ 'NERDTreeGitStatusDirDirty'    : s:NERDTreeGetIndicator('Dirty'),
                \ 'NERDTreeGitStatusDirClean'    : s:NERDTreeGetIndicator('Clean')
                \ }

    for [l:name, l:value] in items(l:synmap)
        exec 'syn match ' . l:name . ' #' . escape(l:value, '#~*.\') . '# containedin=NERDTreeFlags'
    endfor

    hi def link NERDTreeGitStatusModified Special
    hi def link NERDTreeGitStatusStaged Function
    hi def link NERDTreeGitStatusRenamed Title
    hi def link NERDTreeGitStatusUnmerged Label
    hi def link NERDTreeGitStatusUntracked Comment
    hi def link NERDTreeGitStatusDirDirty Tag
    hi def link NERDTreeGitStatusDirClean DiffAdd
    " TODO: use diff color
    hi def link NERDTreeGitStatusIgnored DiffAdd
endfunction

function! s:SetupListeners()
    call g:NERDTreePathNotifier.AddListener('init', 'NERDTreeGitStatusRefreshListener')
    call g:NERDTreePathNotifier.AddListener('refresh', 'NERDTreeGitStatusRefreshListener')
    call g:NERDTreePathNotifier.AddListener('refreshFlags', 'NERDTreeGitStatusRefreshListener')
endfunction

call s:NERDTreeGitStatusKeyMapping()
call s:SetupListeners()
