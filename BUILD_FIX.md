# V1 Public Beta build correction

Corrected the Nexora Console PTY backend for Debian 13 / Qt 6.8:

- connect directly to `QSocketNotifier::activated` instead of selecting a two-argument overload that Qt 6.8 does not expose;
- strip ASCII backspace as `QChar(0x08)` instead of the non-existent `QChar::Backspace` member;
- static audit now rejects both broken patterns.
