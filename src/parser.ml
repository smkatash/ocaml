open Arg
open Yojson.Basic
open Yojson.Basic.Util

type turing_arguments = { jsonfile: string; input: string }

type action_direction = 
  | RIGHT
  | LEFT

type state_transition_operation = {
  read: string;
  to_state: string;
  write: string;  
  action: action_direction
}

module StringMap = Map.Make(String)

type machine_parameters = {
  name: string;
  alphabet: string list;
  blank: string;
  states: string list;
  initial: string;
  finals: string list;
  transitions: state_transition_operation list StringMap.t; 
}

exception InvalidInputSchema of string

(* Define usage message *)
let usage_msg = "usage: ft_turing [-h] jsonfile input\n\n
positional arguments:\n
\tjsonfile\tjson description of the machine\n
\tinput\t\tinput of the machine\n
optional arguments:\n
\t-h, --help\tshow this help message and exit"

(* Define invalid input message *)
let error_msg = "Invalid input\n
usage: ft_turing [-h] jsonfile input"

(* Function to check command-line arguments and display usage if needed *)
let parse_input () =
  let args_len = Array.length Sys.argv in
  if args_len = 2 && (Sys.argv.(1) = "-h" || Sys.argv.(1) = "-help") then
    begin
      print_endline usage_msg;
      exit 0
    end
  else if args_len = 3 then
    begin
      let parsed_arguments = {jsonfile=Sys.argv.(1);input = Sys.argv.(2)} in
      parsed_arguments
    end
  else
    begin
      print_endline error_msg;
      exit 1
    end
    
let get_valid_json_format_data_from_file args = 
  let file_path = args.jsonfile in
  if not (Sys.file_exists file_path) then
    begin
      print_endline ("ft_turing: file " ^ file_path ^ " does not exist.");
      exit 1
    end;
  let json_data = from_file file_path in
  json_data 

let extract_json_data json_data = 
  (* Extract name *)
  let name =
    match Util.member "name" json_data |> Util.to_string with
    | exception _ -> raise (InvalidInputSchema (Printf.sprintf "Missing required field: name"))
    | n -> n
  in
  
  (* Extract alphabet *)
  let alphabet =
    let alphabet_json = Util.member "alphabet" json_data |> Util.to_list in
    let alphabet_list = List.map Util.to_string alphabet_json in
    Printf.printf "Extracted alphabet: %s\n" (String.concat ", " alphabet_list);

    (* Check that each element of alphabet is a string of length 1 *)
    let invalid_chars = List.filter (fun char -> String.length char <> 1) alphabet_list in
    if invalid_chars <> [] then
      raise (InvalidInputSchema (Printf.sprintf "Invalid alphabet symbols: %s" (String.concat ", " invalid_chars)));
    alphabet_list
  in
  
  (* Extract blank *)
  let blank =
    match Util.member "blank" json_data |> Util.to_string with
    | exception _ -> failwith "Missing required field: blank"
    | b -> b
  in
  
  (* Extract states *)
  let states =
    let states_json = Util.member "states" json_data |> Util.to_list in
    List.map Util.to_string states_json
  in
  
  (* Extract initial state *)
  let initial =
    match Util.member "initial" json_data |> Util.to_string with
    | exception _ -> failwith "Missing required field: initial"
    | i ->
        (* Check if initial state is in states list *)
        if List.mem i states then
          i
        else
          raise (InvalidInputSchema (Printf.sprintf "Initial state '" ^ i ^ "' not found in states list"))
  in

  (* Extract finals *)
  let finals =
    let finals_json = Util.member "finals" json_data |> Util.to_list in
    let finals_list = List.map Util.to_string finals_json in
    List.iter (fun final_state ->
      if not (List.mem final_state states) then
        raise (InvalidInputSchema (Printf.sprintf "Final state '" ^ final_state ^ "' not found in states list"))
    ) finals_list;
    finals_list
  in


  (* Check if to_state is valid *)
  let is_valid_state to_state = 
    List.mem to_state states
  in

  (* Check if the character is in the alphabet *)
  let is_valid_alphabet char = 
    List.mem char alphabet
  in

  
  (* Function to parse transition operations *)
  let parse_transition_operation seen_reads transition_operation =
    let read = Util.member "read" transition_operation |> Util.to_string in
    let to_state = Util.member "to_state" transition_operation |> Util.to_string in
    let write = Util.member "write" transition_operation |> Util.to_string in
    let action_str = Util.member "action" transition_operation |> Util.to_string in
    
    (* Validate read, write, and to_state *)
    if not (is_valid_alphabet read) then
      raise (InvalidInputSchema (Printf.sprintf "Invalid read symbol: %s" read))
    else if not (is_valid_alphabet write) then
      raise (InvalidInputSchema (Printf.sprintf "Invalid write symbol: %s" write))
    else if not (is_valid_state to_state) then
      raise (InvalidInputSchema (Printf.sprintf "Invalid state: %s" to_state))
    else if List.mem read seen_reads then
      raise (InvalidInputSchema (Printf.sprintf "Duplicate read symbol: %s" read))
    else
      let action =
        match action_str with
        | "RIGHT" -> RIGHT
        | "LEFT" -> LEFT
        | _ -> raise (InvalidInputSchema "Invalid action in transition")
      in
      Some { read; to_state; write; action }, read :: seen_reads
  in

  (* Extract transitions *)
  let transitions = 
    (* Step 1: Extract the transitions field *)
    let transitions_object = Util.member "transitions" json_data |> Util.to_assoc in

    (* Step 2: Parse each state's transitions into a list of transition_operations *)
    let parse_state_transition seen_reads state_transitions =
      let seen_reads = [] in
      match state_transitions with
      | `List transitions ->
          List.fold_left (fun (acc, seen_reads) transition_operation ->
            match parse_transition_operation seen_reads transition_operation with
            | Some transition, new_seen_reads -> (transition :: acc, new_seen_reads)
            | None, new_seen_reads -> (acc, new_seen_reads) 
      ) ([], seen_reads) transitions
      | _ -> ([], seen_reads)
    in

    (* Step 3: Fold over the transitions object and build the transitions map *)
    List.fold_left (fun (map, seen_reads) (state, state_transitions) ->
      (* Parse state transitions and get updated map and seen_reads *)
      let transitions_list, new_seen_reads = parse_state_transition seen_reads state_transitions in
      let updated_map = StringMap.add state transitions_list map in
      (updated_map, new_seen_reads)
    ) (StringMap.empty, []) transitions_object  |> fst
    in
    (* Return the final result as a record *)
  { name; alphabet; blank; states; initial; finals; transitions }
    


let check_for_duplicate_values json_data =
  let json_list = to_assoc json_data in
  let keys = List.map fst json_list in
  let rec check = function
    | [] -> ()
    | key :: rest when List.mem key rest -> raise (InvalidInputSchema ("ft_turing: Invalid schema. Duplicates detected."))
    | _ :: rest -> check rest
  in
  check keys

let parse_machine_parameters args = 
  try
     (* Step 1: Get valid JSON data from file *)
     let json_data = get_valid_json_format_data_from_file args in

     (* Step 2: Check for duplicate values in the JSON data *)
     check_for_duplicate_values json_data;
 
     (* Step 3: Extract machine parameters from JSON data *)
     let parsed_input = extract_json_data json_data in
 
     (* Return parsed data *)
     parsed_input
  with
  | InvalidInputSchema msg ->
      Printf.eprintf "Error: %s\n" msg;
      exit 1
  | Yojson.Json_error msg ->
      Printf.eprintf "JSON Error: %s\n" msg;
      exit 1
  | Sys_error msg ->
      Printf.eprintf "System Error: %s\n" msg;
      exit 1

let print_transition transition =
  (* Assuming `transition` is a record with fields `read`, `to_state`, `write`, and `action` *)
  Printf.printf "read: %s, to_state: %s, write: %s, action: %s\n"
    transition.read
    transition.to_state
    transition.write
    (match transition.action with
    | RIGHT -> "RIGHT"
    | LEFT -> "LEFT")

let print_transitions transitions_map =
  StringMap.iter (fun state transitions ->
    (* For each state, print its name and the corresponding transitions *)
    Printf.printf "State: %s\n" state;
    List.iter print_transition transitions;
  ) transitions_map

let print_machine_parameters args =
  print_endline ("name: " ^ args.name);

  (* Print alphabet (array of strings) *)
  let alphabet_str = 
    String.concat ", " args.alphabet
  in
  print_endline ("alphabet: " ^ alphabet_str);


  (* Print blank *)
  print_endline ("blank: " ^ args.blank);

  (* Print states (array of strings) *)
  let states_str = 
    String.concat ", " args.states
  in
  print_endline ("states: " ^ states_str);

  (* Print initial state *)
  print_endline ("initial: " ^ args.initial);
  
  (* Print transitions *)
  print_transitions args.transitions



let () =
  let parsed_arguments = parse_input () in
  print_endline ("jsonfile: " ^ parsed_arguments.jsonfile);
  print_endline ("input: " ^ parsed_arguments.input);
  let args = parse_machine_parameters parsed_arguments in
  print_machine_parameters args
