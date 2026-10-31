
 // ==UserScript==
 // @name         Lichess – Auto-request computer analysis
 // @namespace    https://lichess.org/
 // @version      1.0
 // @description  Automatically request server-side analysis when opening a finished game's analysis board.
 // @match        https://lichess.org/*
 // @run-at       document-idle
 // @noframes
 // @grant        none
 // ==/UserScript==

 (() => {
   'use strict';

   const attempted = new Set();
   let timer = null;

   function requestAnalysisIfAvailable() {
     timer = null;

     // Finished-game review pages have URLs like /abcdefgh or /abcdefgh/white.
     // This intentionally excludes /analysis, studies, and live-game pages.
     if (location.pathname === '/analysis') return;
     const match = /^\/([a-zA-Z0-9]{8})(?:\/(?:white|black))?\/?$/.exec(location.pathname);
     if (!match) return;

     const gameId = match[1];
     if (attempted.has(gameId)) return;

     // This is Lichess's own analysis-request form. It exists only when the
     // server analysis can be requested, rather than already being available.
     const form = document.querySelector(
       '.analyse__underboard__panels form.future-game-analysis:not(.must-login)'
     );
     if (!form) return;

     // Avoid requesting the same game again after a reload of this tab.
     const key = `lichess:auto-analysis:${gameId}`;
     try {
       if (sessionStorage.getItem(key)) return;
       sessionStorage.setItem(key, '1');
     } catch (_) {
       // Continue if browser storage is disabled.
     }

     attempted.add(gameId);

     // Use Lichess's normal submit handler, not a direct or undocumented API call.
     form.requestSubmit();
   }

   function scheduleCheck() {
     // Give Lichess time to attach its form handler after rendering the page.
     if (timer === null) timer = setTimeout(requestAnalysisIfAvailable, 1000);
   }

   scheduleCheck();
   new MutationObserver(scheduleCheck).observe(document.documentElement, {
     childList: true,
     subtree: true,
   });
 })();
