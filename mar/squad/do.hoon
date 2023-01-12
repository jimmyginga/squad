:: first we import our /sur/squad.hoon type defs and expose them directly
::
/-  *squad
:: the mark door takes an $act action in in the outbound case
::
|_  a=act
:: the grow arm converts from an $act to other things
::
++  grow
  |%
  :: we just handle the general noun case and return it unchanged
  ::
  ++  noun  a
  --
:: the grab arm handles conversions from other things to an $act
::
++  grab
  |%
  :: we just handle the noun case and mold it to an $act
  ::
  ++  noun  act
  --
:: grad handles revision control functions, we just delegate such
:: functions to the %noun mark
::
++  grad  %noun
--
