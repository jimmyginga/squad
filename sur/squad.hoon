|%
::    --basic types for our app--
::
:: a squad (group) ID, comprised of the host ship and a
:: fixed resource name
::
+$  gid  [host=@p name=@tas]
:: the title of a squad - this can be changed and has no
:: character constraints, unlike the underlying $gid name
::
+$  title  @t
:: The members of a group - a simple set of ships
::
+$  ppl  (set @p)
:: the metadata of a squad - its title and whether it's
:: public or private
::
+$  squad  [=title pub=?]
::
::    --the structures that we'll store in our app's state--
::
:: The whole lot of squads we know and their metadata -
:: this is part of the agent's state. A map from $gid
:: to $squad
::
::
+$  squads  (map gid squad)
:: access control lists. A map from $gid to $ppl. Whether
:: it's a whitelist or blacklist depends of whether it's
:: set to public or private in the $squad
::
+$  acls  (jug gid @p)
:: current members - those who have actually joined,
:: rather than those who we've merely whitelisted.
::
+$  members  (jug gid @p)
::
::    --input requests/actions and output events/updater--
::
:: these are all the possible actions like creating a
:: new squad, whitelisting a ship, changing the title, etc
::
+$  act
  $%  [%new =title pub=?]
      [%del =gid]
      [%allow =gid =ship]
      [%kick =gid =ship]
      [%join =gid]
      [%leave =gid]
      [%pub =gid]
      [%priv =gid]
      [%title =gid =title]
  ==
:: these are all the possible events that can be sent
:: to subscribers. They're largely the same as $act actions
:: but with a couple extra to initialize state
::
+$  upd
  $%  [%init-all =squads =acls =members]
      [%init =gid =squad acl=ppl =ppl]
      [%del =gid]
      [%allow =gid =ship]
      [%kick =gid =ship]
      [%join =gid =ship]
      [%leave =gid =ship]
      [%pub =gid]
      [%priv =gid]
      [%title =gid =title]
  ==
::
::    --additional--
::
:: this just keeps track of the target page and section
:: for the front-end, so we can use a post/redirect/get
:: pattern while remembering where to focus
::
+$  page  [sect=@t gid=(unit gid) success=?]
--
