:: import our /sur/squad.hoon type definitions and expose
:: its contents
::
/-  *squad
:: import a handful of utility libraries: these make it
:: easier to write agents and less boilerplate
::
/+  default-agent, dbug, agentio
:: import our front-end file from /app/squad/index.hoon -
:: don't worry we'll write this in the next section
::
/=  index  /app/squad/index
::
:: We create a $versioned-state so it's easy to upgrade
:: down the line. Our initial state we tag with %0 and
:: call $state-0. It contains the state types we defined
:: earlier. We also define $card just for convenience,
:: so we don't have to type
:: card:agent:gall every time.
::
|%
+$  versioned-state
  $%  state-0
  ==
+$  state-0  [%0 =squads =acls =members =page]
+$  card  card:agent:gall
--
:: we wrap the whole thing with the dbug library we
:: imported so we can access debug functionality from
:: the dojo later
::
%-  agent:dbug
:: we initialize the state by pinning the default value
:: of our previously defined $state-0 structure, then we
:: name it simply state for convenience
::
=|  state-0
=*  state  -
:: here the agent core proper starts. We declare its type
:: an agent:gall, then we begin with its sample: the bowl.
:: The bowl contains various data like the current date-time,
:: entropy, the ship the current event came from, etc. It's
:: automatically populated by Gall each time an event comes in.
::
^-  agent:gall
|_  bol=bowl:gall
:: here we define some aliases for convenience: "this" refers
:: to the whole agent, def is the default-agent library we
:: imported, and io is the agentio library
::
+*  this  .
    def   ~(. (default-agent this %.n) bol)
    io    ~(. agentio bol)
::
:: on-init is only called once, when the app is first installed.
:: In our case it binds the /squad URL path for the front-end,
:: and also tries to auto-join the "Hello World" demo squad on
:: ~pocwet
::
++  on-init
  ^-  (quip card _this)
  :_  this
  :-  (~(arvo pass:io /bind) %e %connect `/'squad' %squad)
  ?:  =(~pocwet our.bol)  ~
  ~[(~(watch pass:io /hello) [~pocwet %squad] /hello)]
:: on-save is called whenever an app is upgraded or suspended.
:: It exports the app's state so either an upgrade can be
:: performed or it can be archived while suspended
::
++  on-save  !>(state)
:: on-load is called after every upgrade or when a suspended
:: agent is revived. The previously exported state is re-imported
:: and saved to the state location we pinned in the basic setup
:: section
::
++  on-load
  |=  old-vase=vase
  ^-  (quip card _this)
  [~ this(state !<(state-0 old-vase))]
:: on-poke: actions/requests from either the front-end or the
:: local ship
::
++  on-poke
  |=  [=mark =vase]
  |^  ^-  (quip card _this)
  :: assert that only the local ship (and its front-end) can
  :: poke our agent. our.bol is the local ship and src.bol is
  :: the source of the request - it's cryptographically guaranteed
  :: to be correct. We just test for equality here
  ::
  ?>  =(our.bol src.bol)
  :: the mark lets us know whether it's an HTTP request from
  :: the front-end or if it's our %squad-do mark sent directory
  :: from the local ship. We call handle-http or handle-action
  :: depending on which it is.
  ::
  =^  cards  state
    ?+  mark  (on-poke:def mark vase)
      %squad-do             (handle-action !<(act vase))
      %handle-http-request  (handle-http !<([@ta inbound-request:eyre] vase))
    ==
  [cards this]
  :: handle-action contains our HTTP request handling logic
  ::
  ++  handle-http
    |=  [rid=@ta req=inbound-request:eyre]
    ^-  (quip card _state)
    :: if the request doesn't contain a valid session cookie
    :: obtained by logging in to landscape with the web logic
    :: code, we just redirect them to the login page
    ::
    ?.  authenticated.req
      :_  state
      (give-http rid [307 ['Location' '/~/login?redirect='] ~] ~)
    :: if it's authenticated, we test whether it's a GET or
    :: POST request.
    ::
    ?+  method.request.req
      :: if it's neither, we give a method not allowed error.
      ::
      :_  state
      %^    give-http
          rid
        :-  405
        :~  ['Content-Type' 'text/html']
            ['Content-Length' '31']
            ['Allow' 'GET, POST']
        ==
      (some (as-octs:mimes:html '<h1>405 Method Not Allowed</h1>'))
    :: if it's a get request, we call our index.hoon file
    :: with the current app state to generate the HTML and
    :: return it. (we'll write that file in the next section)
    ::
        %'GET'
      :_  state(page *^page)
      (make-200 rid (index bol squads acls members page))
    :: if it's a POST request, we first make sure the body
    :: isn't empty, and redirect back to the index if it is.
    ::
        %'POST'
      ?~  body.request.req  [(index-redirect rid '/squad') state]
      :: otherwise, we decode the querystring in the body
      :: of the request. If it fails to parse, we again redirect
      :: to the index.
      ::
      =/  query=(unit (list [k=@t v=@t]))
        (rush q.u.body.request.req yquy:de-purl:html)
      ?~  query  [(index-redirect rid '/squad') state]
      :: now that it's valid, we convert the key-value pair list
      :: from the querystring into a map from key to value so we
      :: can easily randomly access it
      ::
      =/  kv-map=(map @t @t)  (~(gas by *(map @t @t)) u.query)
      :: next, we decode the requested URL to determine the path
      :: they're requesting - we use the path to determine what
      :: kind of request it is
      ::
      =/  =path
        %-  tail
        %+  rash  url.request.req
        ;~(sfix apat:de-purl:html yquy:de-purl:html)
      :: now we switch on the path, handling the different kinds
      :: of requests. If it's not a known path, we again just
      :: redirect to the index.
      ::
      ?+    path  [(index-redirect rid '/squad') state]
        :: if it's a join request, we get the target and decode it
        :: to a gid, redirecting to the index if it fails
        ::
          [%squad %join ~]
        =/  target=(unit @t)  (~(get by kv-map) 'target-squad')
        ?~  target
          :_  state(page ['join' ~ |])
          (index-redirect rid '/squad#join')
        =/  u-gid=(unit gid)
          %+  rush  u.target
          %+  ifix  [(star ace) (star ace)]
          ;~(plug ;~(pfix sig fed:ag) ;~(pfix fas sym))
        ?~  u-gid
          :_  state(page ['join' ~ |])
          (index-redirect rid '/squad#join')
        :: if we're trying to join our own group, disregard
        ::
        ?:  =(our.bol host.u.u-gid)
          :_  state(page ['join' ~ &])
          (index-redirect rid '/squad#join')
        :: otherwise, pass the join request to handle-action
        :: to process, update the target section in the FE
        ::
        =^  cards  state  (handle-action %join u.u-gid)
        :_  state(page ['join' ~ &])
        (weld cards (index-redirect rid '/squad#join'))
      ::
        :: if it's a new group request, make sure it has
        :: the title and public/private setting
        ::
          [%squad %new ~]
        ?.  (~(has by kv-map) 'title')
          :_  state(page ['new' ~ |])
          (index-redirect rid '/squad#new')
        =/  title=@t  (~(got by kv-map) 'title')
        =/  pub=?  (~(has by kv-map) 'public')
        :: otherwise, pass request to handle-action to process
        ::
        =^  cards  state  (handle-action %new title pub)
        :_  state(page ['new' ~ &])
        (weld cards (index-redirect rid '/squad#new'))
      ::
        :: if it's a change title request, make sure it specifies
        :: the gid and the new title, and decode them
        ::
          [%squad %title ~]
        =/  vals=(unit [gid-str=@t =title])
          (both (~(get by kv-map) 'gid') (~(get by kv-map) 'title'))
        ?~  vals
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        =/  u-gid=(unit gid)
          %+  rush  gid-str.u.vals
          ;~(plug fed:ag ;~(pfix cab sym))
        ?~  u-gid
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: otherwise, pass to handle-action to process and redirect
        :: to index, setting the section anchor to the gid in
        :: question
        ::
        =^  cards  state  (handle-action %title u.u-gid title.u.vals)
        :_  state(page ['title' u-gid &])
        (weld cards (index-redirect rid (crip "/squad#{(trip gid-str.u.vals)}")))
      ::
        :: if it's a squad deletion request, make sure the gid
        :: is specified and it can be successfully decoded
        ::
          [%squad %delete ~]
        ?.  (~(has by kv-map) 'gid')
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        =/  u-gid=(unit gid)
          %+  rush  (~(got by kv-map) 'gid')
          ;~(plug fed:ag ;~(pfix cab sym))
        ?~  u-gid
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: make sure it's actually our squad we're deleting
        ::
        ?.  =(our.bol host.u.u-gid)
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: otherwise, pass to handle-action to process
        ::
        =^  cards  state  (handle-action %del u.u-gid)
        :_  state(page ['generic' ~ &])
        (weld cards (index-redirect rid '/squad'))
      ::
        :: if it's a request to leave a squad, make sure
        :: the gid is specified
        ::
          [%squad %leave ~]
        ?.  (~(has by kv-map) 'gid')
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        =/  u-gid=(unit gid)
          %+  rush  (~(got by kv-map) 'gid')
          ;~(plug fed:ag ;~(pfix cab sym))
        ?~  u-gid
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: make sure  we're not trying to join our own squad
        ::
        ?:  =(our.bol host.u.u-gid)
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: pass the request to handle-action to process
        ::
        =^  cards  state  (handle-action %leave u.u-gid)
        :_  state(page ['generic' ~ &])
        (weld cards (index-redirect rid '/squad'))
      ::
        :: if ti's a request to kick a squad member, make
        :: sure the target ship and gid are specified
        ::
          [%squad %kick ~]
        =/  vals=(unit [gid-str=@t ship-str=@t])
          (both (~(get by kv-map) 'gid') (~(get by kv-map) 'ship'))
        ?~  vals
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        =/  u-gid=(unit gid)
          %+  rush  gid-str.u.vals
          ;~(plug fed:ag ;~(pfix cab sym))
        ?~  u-gid
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: make sure it's our squad
        ::
        ?.  =(host.u.u-gid our.bol)
          :_  state(page ['kick' `u.u-gid |])
          (index-redirect rid (crip "/squad#acl:{(trip gid-str.u.vals)}"))
        =/  u-ship=(unit @p)
          %+  rush  ship-str.u.vals
          %+  ifix  [(star ace) (star ace)]
          ;~(pfix sig fed:ag)
        ?~  u-ship
          :_  state(page ['kick' `u.u-gid |])
          (index-redirect rid (crip "/squad#acl:{(trip gid-str.u.vals)}"))
        :: make sure we're not trying to kick ourselves
        ::
        ?:  =(u.u-ship our.bol)
          :_  state(page ['kick' `u.u-gid |])
          (index-redirect rid (crip "/squad#acl:{(trip gid-str.u.vals)}"))
        :: pass to handle-action to process
        ::
        =^  cards  state  (handle-action %kick u.u-gid u.u-ship)
        :_  state(page ['kick' `u.u-gid &])
        %+  weld
          cards
        (index-redirect rid (crip "/squad#acl:{(trip gid-str.u.vals)}"))
      ::
        :: if it's a request to whitelist someone,
        :: make sure the ship and gid are specified
        ::
          [%squad %allow ~]
        =/  vals=(unit [gid-str=@t ship-str=@t])
          (both (~(get by kv-map) 'gid') (~(get by kv-map) 'ship'))
        ?~  vals
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        =/  u-gid=(unit gid)
          %+  rush  gid-str.u.vals
          ;~(plug fed:ag ;~(pfix cab sym))
        ?~  u-gid
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: make sure it's our own squad also
        ::
        ?.  =(host.u.u-gid our.bol)
          :_  state(page ['kick' `u.u-gid |])
          (index-redirect rid (crip "/squad#acl:{(trip gid-str.u.vals)}"))
        =/  u-ship=(unit @p)
          %+  rush  ship-str.u.vals
          %+  ifix  [(star ace) (star ace)]
          ;~(pfix sig fed:ag)
        ?~  u-ship
          :_  state(page ['kick' `u.u-gid |])
          (index-redirect rid (crip "/squad#acl:{(trip gid-str.u.vals)}"))
        :: pass to handle-action to process
        ::
        =^  cards  state  (handle-action %allow u.u-gid u.u-ship)
        :_  state(page ['kick' `u.u-gid &])
        %+  weld
          cards
        (index-redirect rid (crip "/squad#acl:{(trip gid-str.u.vals)}"))
      ::
        :: if it's a request to make a squad public,
        :: make sure the gid is specified
        ::
          [%squad %public ~]
        ?.  (~(has by kv-map) 'gid')
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        =/  u-gid=(unit gid)
          %+  rush  (~(got by kv-map) 'gid')
          ;~(plug fed:ag ;~(pfix cab sym))
        ?~  u-gid
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: also make sure it's our own squad
        ::
        ?.  =(our.bol host.u.u-gid)
          :_  state(page ['public' `u.u-gid |])
          (index-redirect rid (crip "/squad#{(trip (~(got by kv-map) 'gid'))}"))
        :: pass to handle-action to process
        ::
        =^  cards  state  (handle-action %pub u.u-gid)
        :_  state(page ['public' `u.u-gid &])
        %+  weld
          cards
        (index-redirect rid (crip "/squad#{(trip (~(got by kv-map) 'gid'))}"))
      ::
        :: if it's a request to make the squad private,
        :: make sure the gid is specified
        ::
          [%squad %private ~]
        ?.  (~(has by kv-map) 'gid')
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        =/  u-gid=(unit gid)
          %+  rush  (~(got by kv-map) 'gid')
          ;~(plug fed:ag ;~(pfix cab sym))
        ?~  u-gid
          :_  state(page ['generic' ~ |])
          (index-redirect rid '/squad')
        :: also make sure it's our squad
        ::
        ?.  =(our.bol host.u.u-gid)
          :_  state(page ['public' `u.u-gid |])
          (index-redirect rid (crip "/squad#{(trip (~(got by kv-map) 'gid'))}"))
        :: pass to handle-action to process
        ::
        =^  cards  state  (handle-action %priv u.u-gid)
        :_  state(page ['public' `u.u-gid &])
        %+  weld
          cards
        (index-redirect rid (crip "/squad#{(trip (~(got by kv-map) 'gid'))}"))
      ==
    ==
  :: handle-action contains the core logic for handling
  :: the various $act actions
  ::
  ++  handle-action
    |=  =act
    ^-  (quip card _state)
    :: we switch on the kind of action
    ::
    ?-  -.act
      :: if it's a request to create a new squad, we add
      :: the it to $squads in our state and initialize member
      :: and ACL entries too. We then send an %init
      :: update out to local agents to let them know
      ::
        %new
      =/  =gid  [our.bol (title-to-name title.act)]
      =/  =squad  [title.act pub.act]
      =/  acl=ppl  ?:(pub.act *ppl (~(put in *ppl) our.bol))
      =/  =ppl  (~(put in *ppl) our.bol)
      :_  %=  state
            squads   (~(put by squads) gid squad)
            acls     (~(put by acls) gid acl)
            members  (~(put by members) gid ppl)
          ==
      :~  (fact:io squad-did+!>(`upd`[%init gid squad acl ppl]) ~[/local/all])
      ==
    ::
      :: if it's a deletion request, as long as it's our
      :: squad we delete all we know about it, kick all
      :: remote subscribers and tell alert subscribers
      ::
        %del
      ?>  =(our.bol host.gid.act)
      :_  %=  state
            squads   (~(del by squads) gid.act)
            acls     (~(del by acls) gid.act)
            members  (~(del by members) gid.act)
          ==
      :-  (fact:io squad-did+!>(`upd`[%del gid.act]) ~[/local/all])
      (fact-kick:io /[name.gid.act] squad-did+!>(`upd`[%del gid.act]))
    ::
      :: it it's a request to whitelist (or de-blacklist)
      :: a ship, we update the ACL appropriately and update
      :: both local and remote subscribers
      ::
        %allow
      ?>  =(our.bol host.gid.act)
      ?<  =(our.bol ship.act)
      =/  pub=?  pub:(~(got by squads) gid.act)
      ?:  ?|  &(pub !(~(has ju acls) gid.act ship.act))
              &(!pub (~(has ju acls) gid.act ship.act))
          ==
        `state
      :_  state(acls (?:(pub ~(del ju acls) ~(put ju acls)) gid.act ship.act))
      :~  %+  fact:io
            squad-did+!>(`upd`[%allow gid.act ship.act])
          ~[/local/all /[name.gid.act]]
      ==
    ::
      :: if ti's a request to kick someone, we make sure we're
      :: not kicking ourselves and that it's our squad. Then we
      :: add them to the blacklist or remove them from the
      :: whitelist as the case may be, kick them from the
      :: subscription and update local and remote subscribers
      :: about the kick
      ::
        %kick
      ?>  =(our.bol host.gid.act)
      ?<  =(our.bol ship.act)
      =/  pub=?  pub:(~(got by squads) gid.act)
      ?:  ?|  &(pub (~(has ju acls) gid.act ship.act))
              &(!pub !(~(has ju acls) gid.act ship.act))
          ==
        `state
      :_  %=  state
            acls  (?:(pub ~(put ju acls) ~(del ju acls)) gid.act ship.act)
            members  (~(del ju members) gid.act ship.act)
          ==
      :~  %+  fact:io
            squad-did+!>(`upd`[%kick gid.act ship.act])
          ~[/local/all /[name.gid.act]]
          (kick-only:io ship.act ~[/[name.gid.act]])
      ==
    ::
      :: if it's a request to join a squad, if it's our own
      :: or we are already a member, we do nothing. Otherwise,
      :: we send a join request off to the host ship
      ::
        %join
      ?:  |(=(our.bol host.gid.act) (~(has by squads) gid.act))
        `state
      =/  =path  /[name.gid.act]
      :_  state
      :~  (~(watch pass:io path) [host.gid.act %squad] path)
      ==
    ::
      :: if it's a request to leave a squad, we check it's not
      :: our own, delete all we know about it, unsubscribe from
      :: it and let local subscribers know we've unsubscribed
      ::
        %leave
      ?<  =(our.bol host.gid.act)
      ?>  (~(has by squads) gid.act)
      =/  =path  /[name.gid.act]
      :_  %=  state
            squads   (~(del by squads) gid.act)
            members  (~(del by members) gid.act)
            acls     (~(del by acls) gid.act)
          ==
      :~  (~(leave-path pass:io path) [host.gid.act %squad] path)
          (fact:io squad-did+!>(`upd`[%leave gid.act our.bol]) ~[/local/all])
      ==
    ::
      :: if it's a request to make a squad public, we check
      :: it's ours and that it's not already public, then we
      :: clear the whitelist and change the metadata to public,
      :: then alert local and remote subscribers of the change
      ::
        %pub
      ?>  =(our.bol host.gid.act)
      =/  =squad  (~(got by squads) gid.act)
      ?:  pub.squad  `state
      :_  %=  state
            squads  (~(put by squads) gid.act squad(pub &))
            acls    (~(del by acls) gid.act)
          ==
      :~  %+  fact:io
            squad-did+!>(`upd`[%pub gid.act])
          ~[/local/all /[name.gid.act]]
      ==
    ::
      :: if it's a request to make a squad private, we check
      :: it's ours and it's not already private, then we put all
      :: current members in the whitelist and change its metadata
      :: to private. We then alert local and remote subscribers
      :: of the change.
      ::
        %priv
      ?>  =(our.bol host.gid.act)
      =/  =squad  (~(got by squads) gid.act)
      ?.  pub.squad  `state
      =/  =ppl  (~(got by members) gid.act)
      :_  %=  state
            squads  (~(put by squads) gid.act squad(pub |))
            acls    (~(put by acls) gid.act ppl)
          ==
      :~  %+  fact:io
            squad-did+!>(`upd`[%priv gid.act])
          ~[/local/all /[name.gid.act]]
      ==
    ::
      :: if it's a request to rename the squad, we check it's
      :: ours and that the new title is different to the current,
      :: then we update the title and alert local and remote
      :: subscribers
      ::
        %title
      ?>  =(our.bol host.gid.act)
      =/  =squad  (~(got by squads) gid.act)
      ?:  =(title.squad title.act)
        `state
      :_  state(squads (~(put by squads) gid.act squad(title title.act)))
      :~  %+  fact:io
            squad-did+!>(`upd`[%title gid.act title.act])
          ~[/local/all /[name.gid.act]]
      ==
    ==
  :: this function is used to generate a resource name
  :: for the gid from a title when creating a new squad
  :: It makes sure it's unique and replaces illegal
  :: characters in a @tas with hyphens
  ::
  ++  title-to-name
    |=  =title
    ^-  @tas
    =/  new=tape
      %+  scan
        (cass (trip title))
      %+  ifix
        :-  (star ;~(less aln next))
        (star next)
      %-  star
      ;~  pose
        aln
        ;~  less
          ;~  plug
            (plus ;~(less aln next))
            ;~(less next (easy ~))
          ==
          (cold '-' (plus ;~(less aln next)))
        ==
      ==
    =?  new  ?=(~ new)
      "x"
    =?  new  !((sane %tas) (crip new))
      ['x' '-' new]
    ?.  (~(has by squads) [our.bol (crip new)])
      (crip new)
    =/  num=@ud  1
    |-
    =/  =@tas  (crip "{new}-{(a-co:co num)}")
    ?.  (~(has by squads) [our.bol tas])
      tas
    $(num +(num))
  :: this function creates a HTTP redirect response to a
  :: particular location
  ::
  ++  index-redirect
    |=  [rid=@ta path=@t]
    ^-  (list card)
    (give-http rid [302 ['Location' path] ~] ~)
  :: this function makes a status 200 success response.
  :: It's used to serve the index page.
  ::
  ++  make-200
    |=  [rid=@ta dat=octs]
    ^-  (list card)
    %^    give-http
        rid
      :-  200
      :~  ['Content-Type' 'text/html']
          ['Content-Length' (crip ((d-co:co 1) p.dat))]
      ==
    [~ dat]
  :: this function composes the underlying HTTP responses
  :: to successfully complete and close the connection
  ::
  ++  give-http
    |=  [rid=@ta hed=response-header:http dat=(unit octs)]
    ^-  (list card)
    :~  [%give %fact ~[/http-response/[rid]] %http-response-header !>(hed)]
        [%give %fact ~[/http-response/[rid]] %http-response-data !>(dat)]
        [%give %kick ~[/http-response/[rid]] ~]
    ==
  --
:: on-watch is the agent arm that handles subscription
:: requests
::
++  on-watch
  |=  =path
  |^  ^-  (quip card _this)
  :: if it's an HTTP request that's not from the local
  :: ship, disregard
  ::
  ?:  &(=(our.bol src.bol) ?=([%http-response *] path))
    `this
  :: if it's a local request for ALL state, check it's
  :: actually local and fulfill it with an %init-all $upd
  ::
  ?:  ?=([%local %all ~] path)
    ?>  =(our.bol src.bol)
    :_  this
    :~  %-  fact-init:io
        squad-did+!>(`upd`[%init-all squads acls members])
    ==
  :: if the requested subscription path has only one element,
  :: it means it's probably a remote ship trying to subscribe
  :: for updates forking a squad we host
  ::
  ?>  ?=([@ ~] path)
  :: convert the path into a gid
  ::
  =/  =gid  [our.bol i.path]
  :: get the squad metadata from state
  ::
  =/  =squad  (~(got by squads) gid)
  :: if it's public, make sure we haven't blacklisted
  :: the requester.
  :: 
  ?:  pub.squad
    ?<  (~(has ju acls) gid src.bol)
    :: if they're already a member, just give them the initial
    :: squad state
    ::
    ?:  (~(has ju members) gid src.bol)
      [~[(init gid)] this]
    :: if they're not already a member, add them to members,
    :: give them initial state, and then alert other local
    :: and remote subscribers that they've joined
    ::
    :_  this(members (~(put ju members) gid src.bol))
    :~  (init gid)
        %+  fact:io
          squad-did+!>(`upd`[%join gid src.bol])
        ~[/local/all /[name.gid]]
    ==
  :: if it's a private squad, make sure they're in
  :: the whitelist,
  ::
  ?>  (~(has ju acls) gid src.bol)
  :: if they're already a member, just give them the
  :: initial state
  ::
  ?:  (~(has ju members) gid src.bol)
    [~[(init gid)] this]
  :: otherwise add them to members, give them the initial
  :: state and tell other local and remote subscribers
  :: that they've joined
  ::
  :_  this(members (~(put ju members) gid src.bol))
  :~  (init gid)
      %+  fact:io
        squad-did+!>(`upd`[%join gid src.bol])
      ~[/local/all /[name.gid]]
  ==
  :: this function just composes the %init $upd for new
  :: subscribers
  ::
  ++  init
    |=  =gid
    ^-  card
    %+  fact-init:io  %squad-did
    !>  ^-  upd
    :*  %init
        gid
        (~(got by squads) gid)
        (~(get ju acls) gid)
        (~(got by members) gid)
    ==
  --
:: on-agent handles updates from other people or apps
:: we've subscribed to
::
++  on-agent
  |=  [=wire =sign:agent:gall]
  ^-  (quip card _this)
  :: decode the wire (response tag) to determine which
  :: squad it pertains to
  ::
  ?>  ?=([@ ~] wire)
  =/  =gid  [src.bol i.wire]
  :: next, we'll handle the different kinds of
  :: responses/updates it might be. We just use the
  :: default handler for anything we don't need to
  :: manually handle
  ::
  ?+  -.sign  (on-agent:def wire sign)
    :: if it's an acknowledgement for a subscription
    :: request we previously sent...
    ::
      %watch-ack
    :: if there's no error, the subscription succeeded
    :: so we do nothing.
    ::
    ?~  p.sign
      [~ this]
    :: otherwise there's an error, the subscription failed,
    :: meaning we've been rejected. We give up and delete
    :: all we know about the squad. We also alert local
    :: subscribers that we've been kicked.
    ::
    :_  %=  this
          squads   (~(del by squads) gid)
          acls     (~(del by acls) gid)
          members  (~(del by members) gid)
        ==
    :~  (fact:io squad-did+!>(`upd`[%kick gid our.bol]) ~[/local/all])
    ==
  ::
    :: if it's a kick alert, it may or may not be intentional,
    :: so we just automaticall try to resubscribe
    ::
      %kick
    ?.  (~(has by squads) gid)  `this
    :_  this
    :~  (~(watch pass:io wire) [host.gid %squad] wire)
    ==
  ::
    :: a %fact is a normal update from the publisher
    ::
      %fact
    :: assert it's the %squad-did mark we expect
    ::
    ?>  ?=(%squad-did p.cage.sign)
    :: extract the update
    ::
    =/  =upd  !<(upd q.cage.sign)
    :: switch on what kind of update it is, passing it to
    :: the default handler if it's one we don't expect
    ::
    ?+  -.upd  (on-agent:def wire sign)
      :: if it's an %init update containing the initial
      :: state of a squad, overwrite what we know about
      :: the squad in our state, and pass it on to other
      :: local subscribers
      ::
        %init
      ?.  =(gid gid.upd)  `this
      :-  ~[(fact:io cage.sign ~[/local/all])]
      %=  this
        squads   (~(put by squads) gid squad.upd)
        acls     (~(put by acls) gid acl.upd)
        members  (~(put by members) gid ppl.upd)
      ==
    ::
      :: if the squad has been deleted, delete all we know
      :: about it from our state, alert local subscribers about
      :: the deletion, then leave the subscription
      ::
        %del
      ?.  =(gid gid.upd)  `this
      :_  %=  this
            squads  (~(del by squads) gid)
            acls  (~(del by acls) gid)
            members  (~(del by members) gid)
          ==
      :~  (fact:io cage.sign ~[/local/all])
          (~(leave-path pass:io wire) [src.bol %squad] wire)
      ==
    ::
      :: if it's telling us the squad has whitelisted
      :: (or de-blacklisted) a ship, update the squad's
      :: metadata and ACL in state, then alert local
      :: subscribers of what happened
      ::
        %allow
      ?.  =(gid gid.upd)  `this
      =/  pub=?  pub:(~(got by squads) gid)
      :-  ~[(fact:io cage.sign ~[/local/all])]
      this(acls (?:(pub ~(del ju acls) ~(put ju acls)) gid ship.upd))
    ::
      :: if it's telling us someone's been kicked from
      :: the squad...
      ::
        %kick
      ?.  =(gid gid.upd)  `this
      =/  pub=?  pub:(~(got by squads) gid)
      :: check if it's NOT us who have been kicked. In
      :: this case - blacklist or de-whitelist the ship,
      :: remove them from the squad's member list, and
      :: update local subscribers
      ::
      ?.  =(our.bol ship.upd)
        :-  ~[(fact:io cage.sign ~[/local/all])]
        %=  this
          acls  (?:(pub ~(put ju acls) ~(del ju acls)) gid ship.upd)
          members  (~(del ju members) gid ship.upd)
        ==
      :: if WE'VE been kicked, delete all we know about
      :: the squad and let local subscribers know about
      :: the kick. Then, unsubscribe from further updates.
      ::
      :_  %=  this
            squads   (~(del by squads) gid)
            acls     (~(del by acls) gid)
            members  (~(del by members) gid)
          ==
      :~  (fact:io cage.sign ~[/local/all])
          (~(leave-path pass:io wire) [src.bol %squad] wire)
      ==
    ::
      :: if it's telling us someone joined the squad, update the
      :: member list and alert local subscribers of the join
      ::
        %join
      ?.  =(gid gid.upd)  `this
      :-  ~[(fact:io cage.sign ~[/local/all])]
      this(members (~(put ju members) gid ship.upd))
    ::
      :: if it's saying someone left the group...
        %leave
      ?.  =(gid gid.upd)  `this
      :: check whether it's US, and do nothing if so
      ::
      ?:  =(our.bol ship.upd)  `this
      :: otherwise, update the member list and and let local
      :: subscribers know
      ::
      :-  ~[(fact:io cage.sign ~[/local/all])]
      this(members (~(del ju members) gid ship.upd))
    ::
      :: if it's saying the squad has been made public,
      :: update its metadata and alert local subscribers
      ::
        %pub
      ?.  =(gid gid.upd)  `this
      =/  =squad  (~(got by squads) gid)
      ?:  pub.squad  `this
      :-  ~[(fact:io cage.sign ~[/local/all])]
      %=  this
        squads  (~(put by squads) gid squad(pub &))
        acls    (~(put by acls) gid *ppl)
      ==
    ::
      :: if it's saying the squad has been made private,
      :: update its metadata, move all existing members
      :: to the whitelist, and alert local subscribers
      ::
        %priv
      ?.  =(gid gid.upd)  `this
      =/  =squad  (~(got by squads) gid)
      ?.  pub.squad  `this
      :-  ~[(fact:io cage.sign ~[/local/all])]
      %=  this
        squads  (~(put by squads) gid squad(pub |))
        acls    (~(put by acls) gid (~(get ju members) gid))
      ==
    ::
      :: if it's saying the title has changed, update the
      :: squad's title and alert local subscribers
      ::
        %title
      ?.  =(gid gid.upd)  `this
      =/  =squad  (~(got by squads) gid)
      ?:  =(title.squad title.upd)  `this
      :-  ~[(fact:io cage.sign ~[/local/all])]
      %=  this
        squads  (~(put by squads) gid squad(title title.upd))
      ==
    ==
  ==
:: on-leave handles notifications that someone has
:: unsubscribed from us
::
++  on-leave
  |=  =path
  ^-  (quip card _this)
  :: if it's a local subscriber, do nothing
  ::
  ?.  ?=([@ ~] path)  (on-leave:def path)
  :: if it's from us or they're not even a subscriber,
  :: also do nothing
  ::
  ?:  |(=(src.bol our.bol) (~(any by sup.bol) |=([=@p *] =(src.bol p))))
    `this
  :: otherwise, decode the gid, remove them from the member list,
  :: and alert other local or remote subscribers that they've left
  ::
  =/  =gid  [our.bol i.path]
  :_  this(members (~(del ju members) gid src.bol))
  :~  (fact:io squad-did+!>(`upd`[%leave gid src.bol]) ~[/local/all path])
  ==
:: on-peek handles "scry" requests - local read-only requests
::
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  :: we switch on the scry path, these different "scry
  :: endpoints" produce different information
  ::
  ?+    path  (on-peek:def path)
    :: a request for ALL state
    ::
      [%x %all ~]
    ``noun+!>([squads acls members])
  ::
    :: a request for all squads and their metadata
    ::
      [%x %squads ~]
    ``noun+!>(squads)
  ::
    :: a request for all squad gids (but no metadata)
    ::
      [%x %gids %all ~]
    ``noun+!>(`(set gid)`~(key by squads))
  ::
    :: a request for only the gids of squads we host
    ::
      [%x %gids %our ~]
    =/  gids=(list gid)  ~(tap by ~(key by squads))
    =.  gids  (skim gids |=(=gid =(our.bol host.gid)))
    ``noun+!>(`(set gid)`(~(gas in *(set gid)) gids))
  ::
    :: a request for the metadata of a particular squad
    ::
      [%x %squad @ @ ~]
    =/  =gid  [(slav %p i.t.t.path) i.t.t.t.path]
    ``noun+!>(`(unit squad)`(~(get by squads) gid))
  ::
    :: a request for the blacklist or whitelist for
    :: a particular squad
    ::
      [%x %acl @ @ ~]
    =/  =gid  [(slav %p i.t.t.path) i.t.t.t.path]
    =/  u-squad=(unit squad)  (~(get by squads) gid)
    :^  ~  ~  %noun
    !>  ^-  (unit [pub=? acl=ppl])
    ?~  u-squad
      ~
    `[pub.u.u-squad (~(get ju acls) gid)]
  ::
    :: a request for all current members of a particular
    :: squad
    ::
      [%x %members @ @ ~]
    =/  =gid  [(slav %p i.t.t.path) i.t.t.t.path]
    ``noun+!>(`ppl`(~(get ju members) gid))
  ::
    :: a request for the titles of all squads. This is intended
    :: to be used from a front-end, unlike the others, so it
    :: produces JSON rather than just a noun
    ::
      [%x %titles ~]
    :^  ~  ~  %json
    !>  ^-  json
    :: make a JSON array
    ::
    :-  %a
    :: sort all the titles alphabetically
    ::
    %+  turn
      (sort ~(tap by squads) |=([[* a=@t *] [* b=@t *]] (aor a b)))
    :: convert each one to a JSON object like:
    :: {"gid": {"host": "~zod", "name": "foo"}, "title": "some title"}
    ::
    |=  [=gid =@t ?]
    ^-  json
    %-  pairs:enjs:format
    :~  :-  'gid'
        %-  pairs:enjs:format
        :~  ['host' s+(scot %p host.gid)]
            ['name' s+name.gid]
        ==
        ['title' s+t]
    ==
  ==
:: on-arvo handles kernel responses. The only interaction we
:: have with the kernel directly is when we bind the /squad
:: URL path, so we just take the acknowledgement of that and
:: print an error if it failed
::
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ?.  ?=([%bind ~] wire)
    (on-arvo:def [wire sign-arvo])
  ?.  ?=([%eyre %bound *] sign-arvo)
    (on-arvo:def [wire sign-arvo])
  ~?  !accepted.sign-arvo
    %eyre-rejected-squad-binding
  `this
:: on-fail is called when our agent crashes. We'll just leave
:: it to the default handler in default-agent to print the error
::
++  on-fail  on-fail:def
--
