extensions [ gis ]

globals [
  buildings-dataset
  roads-dataset
  cur-day
  cur-hour
  cur-min
  max-speed
  min-speed
  crime-history-sf
  attract-sf
  victim-record-sf
  guardian-sf
  aware-sf
  time-weight
  density-weight
  crime-history-weight
  meters-per-patch
  citizen-attract-radius
  robbery-impact-radius
  criminal-home-radius
  criminal-guardian-radius
  density-radius
  robbery-num
]
breed [nodes node]
nodes-own [attract crime-history density recent-crime]

breed [ citizens citizen ]
citizens-own [ speed node-home node-goal cur-goal awake-time return-time cur-node path c-type on-roam? active? cur-speed awareness prob-out victim-record recent-crime ]

breed [ criminals criminal ]
criminals-own [ speed node-home node-goal cur-goal awake-time return-time cur-node path active? cur-speed ]

breed [ searchers search ]
searchers-own [ memory cost total-expected-cost localization active? ]

to setup
  clear-all

  ; Load all of our datasets
  set buildings-dataset gis:load-dataset "data/buildings2.shp"
  set roads-dataset gis:load-dataset "data/roads.shp"
  ; Set the world envelope to the union of all of our dataset's envelopes
  gis:set-world-envelope (gis:envelope-union-of (gis:envelope-of buildings-dataset)
                                                (gis:envelope-of roads-dataset))
  display-roads
  display-buildings
  setup-paths-graph

  set meters-per-patch meters-per-patch-function
  set max-speed 2.4 * 60 / meters-per-patch
  set min-speed 1.6 * 60 / meters-per-patch
  set time-weight 0.4
  set density-weight 0.3
  set crime-history-weight 0.3

  set density-radius 100 / meters-per-patch
  set robbery-impact-radius 100 / meters-per-patch
  set citizen-attract-radius 100 / meters-per-patch
  set criminal-home-radius 100 / meters-per-patch
  set criminal-guardian-radius 100 / meters-per-patch


  set crime-history-sf 0.1
  set attract-sf 0.1
  set victim-record-sf 0.1
  set guardian-sf 0.1
  set aware-sf 0.1

  setup-citizens
  setup-criminals
  set cur-day 0
  set cur-hour 0
  set cur-min 0

  set robbery-num 0

  ask nodes [
    density-at-node density-radius
  ]

  reset-ticks

end

to go

  time-update
  ask citizens [
     citizen-schedule
     victim-record-update
   ]

  ask criminals [
    criminal-schedule
    robbery
  ]

  ask nodes [
    density-at-node density-radius
    environment-attract cur-hour
    crime-history-node
  ]

  tick ;; tick called after patch/turtle updates but before plots
end

to-report random-normal-in-bounds [mid dev mmin mmax]
  let result random-normal mid dev
  if result < mmin or result > mmax
    [ report random-normal-in-bounds mid dev mmin mmax ]
  report result
end

to time-update
  set cur-min (cur-min + 1)

  if cur-min = 60 [
    set cur-hour (cur-hour + 1)
    set cur-min 0
  ]

  if cur-hour = 24 [
    set cur-day (cur-day + 1)
    set cur-hour 0
  ]
end

to-report teta-at [t]
  report abs(0.1301 * t - 1.387) / 1.6053;
end

to environment-attract [t]
  set attract (attract + attract-sf * ((density * density-weight + teta-at (t - 1) * time-weight + (1 - crime-history) * crime-history-weight) / (density-weight + time-weight + crime-history-weight)))
end

to-report heuristic [#Goal]
  report [distance [localization] of myself] of #Goal
end

to display-roads
  gis:set-drawing-color gray
  gis:draw roads-dataset 1
end

to display-buildings
  gis:set-drawing-color blue
  gis:draw buildings-dataset 1
end

to setup-paths-graph
  set-default-shape nodes "circle"
  foreach polylines-of roads-dataset 3 [ ?1 ->
    (foreach butlast ?1 butfirst ?1 [ [??1 ??2] -> if ??1 != ??2 [ ;; skip nodes on top of each other due to rounding
      let n1 new-node-at first ??1 last ??1
      let n2 new-node-at first ??2 last ??2
      ask n1 [create-link-with n2]
    ] ])
  ]
  ask nodes [hide-turtle]
end

to-report polylines-of [dataset decimalplaces]
  let polylines gis:feature-list-of dataset                              ;; start with a features list
  set polylines map [ ?1 -> first ?1 ] map [ ?1 -> gis:vertex-lists-of ?1 ] polylines      ;; convert to vertex lists
  set polylines map [ ?1 -> map [ ??1 -> gis:location-of ??1 ] ?1 ] polylines                ;; convert to netlogo float coords.
  set polylines remove [] map [ ?1 -> remove [] ?1 ] polylines                    ;; remove empty poly-sets .. not visible
  set polylines map [ ?1 -> map [ ??1 -> map [ ???1 -> precision ???1 decimalplaces ] ??1 ] ?1 ] polylines        ;; round to decimalplaces
    ;; note: probably should break polylines with empty coord pairs in the middle of the polyline
  report polylines ;; Note: polylines with a few off-world points simply skip them.
end

to-report new-node-at [x y] ; returns a node at x,y creating one if there isn't one there.
  let n nodes with [xcor = x and ycor = y]
  ifelse any? n [
    set n one-of n
  ] [
    create-nodes 1 [
      setxy x y
      set size 1
      set n self
      set crime-history precision random-normal-in-bounds 0.5 0.5 0 1 4
      set recent-crime false
    ]
  ]
  report n
end

to-report meters-per-patch-function
  let world gis:world-envelope ; [ minimum-x maximum-x minimum-y maximum-y ]
  let x-meters-per-patch (item 1 world - item 0 world) / (max-pxcor - min-pxcor)
  let y-meters-per-patch (item 3 world - item 2 world) / (max-pycor - min-pycor)
  report mean list x-meters-per-patch y-meters-per-patch
end

to crime-history-node

  ifelse recent-crime [
    set crime-history 1
    set recent-crime false
  ][
    set crime-history crime-history * crime-history-sf
  ]
end

to victim-record-update
  ifelse recent-crime [
    set victim-record 1
    set recent-crime false
  ][
    set victim-record victim-record * victim-record-sf
  ]
end

to-report affecting-node-attract [agent]
  report [attract] of min-one-of nodes in-radius citizen-attract-radius [distance agent]
end

to victim-awareness
  set awareness (victim-record + (1 - affecting-node-attract myself))/ 2
end

to setup-citizens
  set-default-shape citizens "circle"

  create-citizens number-of-agents[
    set color green
    set size 0.5 ;; use meters-per-patch??
    set speed min-speed + random-float (max-speed - min-speed)
    set cur-speed speed
    let l one-of links
    set node-goal one-of nodes
    while [node-goal = [end1] of l][
      set node-goal one-of nodes
    ]

    set awake-time floor random-normal-in-bounds 8 2 0 23
    set return-time floor random-normal-in-bounds 18 2 0 23
    set node-home ([end1] of l)
    set path (A* node-home node-goal)
    move-to (node-home)
    face item 1 path
    set cur-goal node-goal


    set active? false
    set on-roam? false
    set cur-node 0

    set victim-record precision random-normal-in-bounds 0.5 0.5 0 1 4
    set recent-crime false

    set prob-out precision random-float 1 4
  ]


end

to setup-criminals
  set-default-shape criminals "circle"
  ;; let citizen-size 10 * meters-per-patch

  create-criminals number-of-agents * 0.1 [
    set color red
    set size 0.5 ;; use meters-per-patch??
    set speed min-speed + random-float (max-speed - min-speed)
    set cur-speed speed
    let l one-of links
    set node-goal one-of nodes
    while [node-goal = [end1] of l and ([distance node-home] of node-goal <= criminal-home-radius)] [
      set node-goal one-of nodes
    ]

    set awake-time floor random-normal-in-bounds 14 2 0 23
    set return-time floor random-normal-in-bounds 4 2 0 23

    set node-home ([end1] of l)
    set path (A* node-home node-goal)
    move-to (node-home)
    face item 1 path
    set cur-goal node-goal


    set active? false
    set cur-node 0
  ]


end

to-report at-home?
  let flag false

  if xcor = [xcor] of node-home and ycor = [ycor] of node-home[
    set flag true
  ]

  report flag
end

to-report at-goal?
  let flag false

  if xcor = [xcor] of cur-goal and  ycor = [ycor] of cur-goal[
    set flag true
  ]
  report flag
end

to density-at-node [radius]

  set density count citizens in-radius radius

end

to citizen-schedule

  if (cur-hour = awake-time or cur-hour = return-time) and not active? [
    set active? true
  ]

  if (cur-hour >= return-time and at-home?) or (cur-hour > awake-time and cur-hour < return-time and node-goal = cur-goal and at-goal?) and active?[
    set active? false
  ]

  ifelse active? [
    move-agent cur-speed
  ][
    if at-goal? [
      ifelse cur-goal != node-home [
        set cur-goal node-home
        set path reverse path
      ][
        set cur-goal node-goal
        set path reverse path
      ]

    ]
    set cur-node 0
    face item 1 path
  ]



end


to-report max-target-attract-in-loc
  report [((1 - affecting-node-attract myself) * guardian-sf + (1 - awareness) * aware-sf) / (guardian-sf + aware-sf)] of max-one-of citizens [ ((1 - affecting-node-attract myself) * guardian-sf + (1 - awareness) * aware-sf) / (guardian-sf + aware-sf)]
end

to robbery
  let prob precision random-normal-in-bounds 0.5 0.5 0 1 4

  if (prob < max-target-attract-in-loc)[
    set robbery-num robbery-num + 1
  ]
end


to criminal-schedule
  if (cur-hour = awake-time) [
    set active? true
  ]

  if (cur-hour >= return-time and at-home?) and active?[
    set active? false
  ]

  if active? [
    move-agent cur-speed
  ]

  if at-goal? [
    ifelse cur-hour >= return-time[
      set path reverse path

    ][
      set cur-goal node-goal
      set path reverse path
    ]
   set cur-node 0
   face item 1 path
  ]

end

to move-agent [dist] ;; citizen proc
  let aux_p [path] of self

  if cur-node + 1 < length aux_p [

    let dxnode distance item (cur-node + 1) [path] of self

    if length aux_p > 1 [
      ifelse dxnode > dist [
        forward dist
      ] [
        set cur-node (cur-node + 1)
        move-to item cur-node aux_p

        ifelse (cur-node + 1) < length aux_p [
          face item (cur-node + 1) aux_p
        ] [
          face item (cur-node - 1) aux_p
        ]

        move-agent dist - dxnode
      ]
    ]
  ]

end

to-report A* [#Start #Goal]
  ; Create a searcher for the Start node
  ask #Start
  [
    hatch-searchers 1
    [
      set shape "circle"
      set color white
      set localization myself
      set memory (list localization) ; the partial path will have only this node at the beginning
      set cost 0
      set total-expected-cost cost + heuristic #Goal ; Compute the expected cost
      set active? true ; It is active, because we didn't calculate its neighbors yet
  ] ]
  ; The main loop will run while the Goal has not been reached and we have active
  ;   searchers to inspect. That means that a path connecting start and goal is
  ;   still possible.
  while [not any? searchers with [localization = #Goal] and any? searchers with [active?]]
  [
    ; From the active searchers we take one with the minimal expected total cost to the goal
    ask min-one-of (searchers with [active?]) [total-expected-cost]
    [
      ; We will explore its neighbors in this block, so we deactivated it
      set active? false
      ; Store this searcher and its localization in temporal variables to facilitate their use
      let this-searcher self
      let Lorig localization
      ; For every neighbor node of this location...
      ask ([link-neighbors] of Lorig)
      [
        ; Take the link that connect it to the Location of the searcher
        let connection link-with Lorig
        ; Compute the cost to reach the neighbor in this path as the previous cost plus the
        ;   length of the link
        let c ([cost] of this-searcher) + [link-length] of connection
        ; Maybe in this node there are other searchers (comming from other nodes).
        ; If this new path is better than others to reach this node, then we put a
        ;   new searcher and remove the old ones. Search-in-loc is an auxiliary
        ;   report that you can find bellow.
        if not any? searchers-in-loc with [cost < c]
        [
          hatch-searchers 1
          [
            set shape "circle"
            set color white
            set localization myself                  ; The location of the new
                                                     ;   searcher is this neighbor node
            set memory lput localization ([memory] of this-searcher) ; The path is
                                                     ; built from the original searcher
            set cost c                               ; Real cost to reach this node
            set total-expected-cost cost + heuristic #Goal ; Expected cost to reach the
                                                           ;   goal by using this path
            set active? true                         ; It is active to be explored
            ask other searchers-in-loc [die]         ; Remove other searchers in this node
  ] ] ] ] ]
  ; When the loop has finished, we have two options:
  ;   - no path has been built,
  ;   - or a searcher has reached the goal
  ; By default the return will be false (no path has been built)
  let res false
  ; But if it is the second option...
  if any? searchers with [localization = #Goal]
  [
    ; we will return the path stored in the memory of the searcher that reached the goal
    let lucky-searcher one-of searchers with [localization = #Goal]
    set res [memory] of lucky-searcher
  ]
  ; Remove the searchers (we don't want the A* report to leave any trash)
  ask searchers [die]
  ; And report the result
  report res
end

to-report searchers-in-loc
  report searchers with [localization = myself]
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
911
712
-1
-1
16.90244
1
10
1
1
1
0
1
1
1
-20
20
-20
20
0
0
1
ticks
30.0

BUTTON
123
162
186
195
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
16
163
89
196
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1044
321
1101
366
Hour
cur-hour
17
1
11

MONITOR
1120
322
1183
367
Minutes
cur-min
17
1
11

MONITOR
969
322
1026
367
Day
cur-day
17
1
11

SLIDER
942
186
1158
219
number-of-agents
number-of-agents
1
10000
1.0
100
1
NIL
HORIZONTAL

PLOT
942
23
1142
173
Robbery
Hour
Num of Robbery
0.0
100.0
0.0
100.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot count robbery-num"

@#$#@#$#@
## DO QUE SE TRATA?

Esta é a primeira fase do projeto que pertecene ao grupo CrimAi da Universidade Federal de Lavras. Nele, o centro da cidade de Lavras é representado através de um arquivo de coordenadas e pedestres, simbolizados por pontos vermelhos, se movimentam pelas ruas.

## COMO FUNCIONA?

Os arquivos de coordenadas, chamados Shapefile, são replicados e desenhados na tela através da extensão GIS do programa NetLogo. A partir disso, as ruas e prédios apresentam de cores diferentes, arbitrárias, para que os agentes, no caso pedestres, se movimentem.

Para o movimento nas ruas, é necessário utilizar de conceitos de grafos, mas no momento, apenas movimentos que seguem as linhas estão sendos utilizados.

## MUDANÇAS PARA A PRÓXIMA VERSÃO

* Movimentos mais verossímeis para os pedestres.

* Controle das variáveis do modelo (e.g. quantidade de pedestres, horas, luz).

* Gráficos para mostrar o andamento da simulação.

* Lógica para distribuição fidegina da população na área tratada.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
