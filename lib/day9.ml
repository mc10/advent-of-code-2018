open! Core
open! Async

let game_re =
  Re.Perl.compile_pat "(\\d+) players; last marble is worth (\\d+) points"
;;

module Game = struct
  type t =
    { player_count : int
    ; last_marble : int
    }
  [@@deriving sexp]
end

let read_game file_name =
  let%map game_string =
    match%map Reader.file_lines file_name with
    | [ game_string ] -> game_string
    | [] -> raise_s [%message "No string found"]
    | _ :: _ -> raise_s [%message "More than one line found"]
  in
  let game_groups = Re.exec game_re game_string in
  let player_count = Re.Group.get game_groups 1 |> Int.of_string in
  let last_marble = Re.Group.get game_groups 2 |> Int.of_string in
  { Game.player_count; last_marble }
;;

let rec clockwise marbles curr i =
  match Ordering.of_int i with
  | Equal -> curr
  | Greater ->
    let next =
      match Doubly_linked.next marbles curr with
      | Some next -> next
      | None ->
        (* Connect the end of the marble circle to the beginning. *)
        Doubly_linked.first_elt marbles |> Option.value_exn
    in
    clockwise marbles next (i - 1)
  | Less ->
    let prev =
      match Doubly_linked.prev marbles curr with
      | Some prev -> prev
      | None ->
        (* Connect the beginning of the marble circle to the end. *)
        Doubly_linked.last_elt marbles |> Option.value_exn
    in
    clockwise marbles prev (i + 1)
;;

let play_marble_game (game : Game.t) =
  let process_marble
      (player_points, marbles, curr)
      marble
    : _ Base.Continue_or_stop.t
    =
    let player_points, marbles, curr =
      if Int.(marble mod 23 = 0)
      then (
        let curr_player = marble mod game.player_count in
        let score =
          Map.find player_points curr_player
          |> Option.value ~default:0
        in
        let marble_7 = clockwise marbles curr (-7) in
        let curr = clockwise marbles marble_7 1 in
        Doubly_linked.remove marbles marble_7;
        let score = score + marble + Doubly_linked.Elt.value marble_7 in
        let player_points = Map.set player_points ~key:curr_player ~data:score in
        player_points, marbles, curr
      )
      else (
        let marble_1 = clockwise marbles curr 1 in
        let curr = Doubly_linked.insert_after marbles marble_1 marble in
        player_points, marbles, curr)
    in
    if Int.(marble = game.last_marble)
    then Stop player_points
    else Continue (player_points, marbles, curr)
  in
  let next_marbles =
    Sequence.unfold ~init:1 ~f:(fun next -> Some (next, next + 1))
  in
  let player_points = Int.Map.empty in
  let marbles = Doubly_linked.of_list [ 0 ] in
  let curr = Doubly_linked.last_elt marbles |> Option.value_exn in
  Sequence.fold_until
    next_marbles
    ~init:(player_points, marbles, curr)
    ~f:process_marble
    ~finish:(fun _ -> raise_s [%message "No next marble found"])
;;

let find_high_score game =
  let player_points = play_marble_game game in
  Map.data player_points
  |> List.max_elt ~compare:Int.compare
  |> Option.value ~default:0
;;

let part_1 file_name =
  let%map game = read_game file_name in
  let high_score = find_high_score game in
  printf "High score: %d\n" high_score
;;

let part_2 file_name =
  let%map game = read_game file_name in
  let game = { game with last_marble = game.last_marble * 100 } in
  let high_score = find_high_score game in
  printf "High score: %d\n" high_score
;;

let cmd_part_1 =
  Command.async
    ~summary:"Part 1"
    (let open Command.Let_syntax in
     let%map_open input_file =
       flag "-input" (required file) ~doc:"FILE path to input file"
     in
     fun () -> part_1 input_file)
;;

let cmd_part_2 =
  Command.async
    ~summary:"Part 2"
    (let open Command.Let_syntax in
     let%map_open input_file =
       flag "-input" (required file) ~doc:"FILE path to input file"
     in
     fun () -> part_2 input_file)
;;

let command =
  Command.group
    ~summary:"Day 9"
    [ "part-1", cmd_part_1; "part-2", cmd_part_2 ]
;;

let () = Command.run command