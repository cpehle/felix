(* Universal Character Names in identifiers:
   Below, a table of letters acceptable in identifiers.

   Source: ISO Standard C++, Appendix E.
   Which came from ISO/IEC PDTR 10176, produced by
   ISO/IEC JTC1/SC22/WG20 (internationalisation)

   Characters must be in the range shown
   inclusive. This list must be strictly ordered.

   Felix also allows
   underscore, prime, and digits in identifiers.
   Digits must not be first.
*)
open Flx_string

let ucs_id_ranges = [
  (* ASCII *)
  (0x002d,0x002d); (* dash - *)
  (0x0041,0x005a);
  (0x0061,0x007a);

  (* Latin *)
  (0x00c0,0x00d6);
  (0x00d8,0x00f6);
  (0x00f8,0x01f5);
  (0x01fa,0x0217);
  (0x0250,0x02a8);

  (* Greek *)
  (0x0384,0x0384);
  (0x0388,0x038a);
  (0x038c,0x038c);
  (0x038e,0x03a1);
  (0x03a3,0x03ce);
  (0x03d0,0x03d6);
  (0x03da,0x03da);
  (0x03dc,0x03dc);
  (0x03de,0x03de);
  (0x03e0,0x03e0);
  (0x03e2,0x03f3);

  (* Cyrillic *)
  (0x0401,0x040d);
  (0x040f,0x044f);
  (0x0451,0x045c);
  (0x045e,0x0481);
  (0x0490,0x04c4);
  (0x04c7,0x04c4);
  (0x04cb,0x04cc);
  (0x04d0,0x04eb);
  (0x04ee,0x04f5);
  (0x04f8,0x04f9);

  (* Armenian *)
  (0x0531,0x0556);
  (0x0561,0x0587);
  (0x04d0,0x04eb);

  (* Hebrew *)
  (0x05d0,0x05ea);
  (0x05f0,0x05f4);

  (* Arabic *)
  (0x0621,0x063a);
  (0x0640,0x0652);
  (0x0670,0x06b7);
  (0x06ba,0x06be);
  (0x06c0,0x06ce);
  (0x06e5,0x06e7);

  (* Devanagari *)
  (0x0905,0x0939);
  (0x0958,0x0962);

  (* Bengali *)
  (0x0985,0x098c);
  (0x098f,0x0990);
  (0x0993,0x09a8);
  (0x09aa,0x09b0);
  (0x09b2,0x09b2);
  (0x09b6,0x09b9);
  (0x09dc,0x09dd);
  (0x09df,0x09e1);
  (0x09f0,0x09f1);

  (* Gurmukhi *)
  (0x0a05,0x0a0a);
  (0x0a0f,0x0a10);
  (0x0a13,0x0a28);
  (0x0a2a,0x0a30);
  (0x0a32,0x0a33);
  (0x0a35,0x0a36);
  (0x0a38,0x0a39);
  (0x0a59,0x0a5c);
  (0x0a5e,0x0a5e);

  (* Gunjarati *)
  (0x0a85,0x0a8b);
  (0x0a8d,0x0a8d);
  (0x0a8f,0x0a91);
  (0x0a93,0x0aa8);
  (0x0aaa,0x0ab0);
  (0x0ab2,0x0ab3);
  (0x0ab5,0x0ab9);
  (0x0ae0,0x0ae0);

  (* Oriya *)
  (0x0b05,0x0b0c);
  (0x0b0f,0x0b10);
  (0x0b13,0x0b28);
  (0x0b2a,0x0b30);
  (0x0b32,0x0b33);
  (0x0b36,0x0b39);
  (0x0b5c,0x0b5d);
  (0x0b5f,0x0b61);

  (* Tamil *)
  (0x0b85,0x0b8a);
  (0x0b8e,0x0b90);
  (0x0b92,0x0b95);
  (0x0b99,0x0b9a);
  (0x0b9c,0x0b9c);
  (0x0b9e,0x0b9f);
  (0x0ba3,0x0ba4);
  (0x0ba8,0x0baa);
  (0x0bae,0x0bb5);
  (0x0bb7,0x0bb9);

  (* Telugu *)
  (0x0c05,0x0c0c);
  (0x0c0e,0x0c10);
  (0x0c12,0x0c28);
  (0x0c2a,0x0c33);
  (0x0c35,0x0c39);
  (0x0c60,0x0c61);

  (* Kannada *)
  (0x0c85,0x0c8c);
  (0x0c8e,0x0c90);
  (0x0c92,0x0ca8);
  (0x0caa,0x0cb3);
  (0x0cb5,0x0cb9);
  (0x0ce0,0x0ce1);

  (* Malayam *)
  (0x0d05,0x0d0c);
  (0x0d0e,0x0d10);
  (0x0d12,0x0d28);
  (0x0d2a,0x0d39);
  (0x0d60,0x0d61);

  (* Thai *)
  (0x0e01,0x0e30);
  (0x0e32,0x0e33);
  (0x0e40,0x0e46);
  (0x0e4f,0x0e5b);

  (* Lao *)
  (0x0e81,0x0e82);
  (0x0e84,0x0e84);
  (0x0e87,0x0e88);
  (0x0e8a,0x0e8a);
  (0x0e0d,0x0e0d);
  (0x0e94,0x0e97);
  (0x0e99,0x0e9f);
  (0x0ea1,0x0ea3);
  (0x0ea5,0x0ea5);
  (0x0ea7,0x0ea7);
  (0x0eaa,0x0eab);
  (0x0ead,0x0eb0);
  (0x0eb2,0x0eb3);
  (0x0ebd,0x0ebd);
  (0x0ec0,0x0ec4);
  (0x0ec6,0x0ec6);

  (* Georgian *)
  (0x10a0,0x10c5);
  (0x10d0,0x10f6);

  (* Hangul Jamo *)
  (0x1100,0x1159);
  (0x1161,0x11a2);
  (0x11a8,0x11f9);
  (0x11d0,0x11f6);

  (* Latin extensions *)
  (0x1e00,0x1e9a);
  (0x1ea0,0x1ef9);

  (* Greek extended *)
  (0x1f00,0x1f15);
  (0x1f18,0x1f1d);
  (0x1f20,0x1f45);
  (0x1f48,0x1f4d);
  (0x1f50,0x1f57);
  (0x1f59,0x1f59);
  (0x1f5b,0x1f5b);
  (0x1f5d,0x1f5d);
  (0x1f5f,0x1f7d);
  (0x1f80,0x1fb4);
  (0x1fb6,0x1fbc);
  (0x1fc2,0x1fc4);
  (0x1fc6,0x1fcc);
  (0x1fd0,0x1fd3);
  (0x1fd6,0x1fdb);
  (0x1fe0,0x1fec);
  (0x1ff2,0x1ff4);
  (0x1ff6,0x1ffc);


  (* Hiragana *)
  (0x3041,0x3094);
  (0x309b,0x309e);

  (* Katakana *)
  (0x30a1,0x30fe);

  (* Bopmofo *)
  (0x3105,0x312c);

  (* CJK Unified Ideographs *)
  (0x4e00,0x9fa5);

  (* CJK Compatibility Ideographs *)
  (0xf900,0xfa2d);

  (* Arabic Presentation Forms *)
  (0xfb1f,0xfb36);
  (0xfb38,0xfb3c);
  (0xfb3e,0xfb3e);
  (0xfb40,0xfb41);
  (0xfb42,0xfb44);
  (0xfb46,0xfbb1);
  (0xfbd3,0xfd35);

  (* Arabic Presentation Forms-A *)
  (0xfd50,0xfd85);
  (0xfd92,0xfbc7);
  (0xfdf0,0xfdfb);

  (* Arabic Presentation Forms-B *)
  (0xfe70,0xfe72);
  (0xfe74,0xfe74);
  (0xfe76,0xfefc);

  (* Half width and Fullwidth Forms *)
  (0xff21,0xff3a);
  (0xff41,0xff5a);
  (0xff66,0xffbe);
  (0xffc2,0xffc7);
  (0xffca,0xffcf);
  (0xffd2,0xffd7);
  (0xffd2,0xffd7);
  (0xffda,0xffdc)
]

exception Found
let check_code x =
  try
    List.iter
    (fun (first, last) ->
      (* print_endline ((hex4 first) ^"-"^(hex4 last)); *)
      if x < first
      then raise (Flx_exceptions.LexError ("Bad letter \\U"^hex8 x^" in identifier"))
      ;
      if x <= last
      then raise Found
    )
    ucs_id_ranges
    ;
    raise (Flx_exceptions.LexError ("Bad letter \\U"^hex8 x^" in identifier"))
  with Found -> ()

let utf8_to_ucn s =
  let s' = Buffer.create 1000 in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    let u,i' =
      if s.[!i]='\\'
      then begin
        incr i;
        if !i>n
        then failwith ("Slosh at end of identifier " ^ s)
        else if s.[!i] = 'u'
        then begin
          incr i;
          if n - !i < 4
          then failwith
          (
            "\\u at col "^
            string_of_int !i ^
            " must be followed by 4 hex digits"
          )
          else
            let u = hexint_of_string (String.sub s !i 4) in
            u,!i + 4
        end else if s.[!i] = 'U'
        then begin
          incr i;
          if n - !i < 8
          then failwith
          (
            "\\U at col "^
            string_of_int !i ^
            " must be followed by 8 hex digits"
          )
          else
            let u = Flx_string.hexint_of_string (String.sub s !i 8) in
            u,!i + 8
        end else failwith
        (
          "Slosh in identifier '"^
          s^
          "' col "^
          string_of_int (!i+1)^
          "must be followed by u or U"
        )
      end
      else
       parse_utf8 s !i
    in
      i := i';
      if (u <> 0x27) (* apostrophe *)
      && (u <> 0x5F) (* underscore *)
      && ((u < 0x30) or (u > 0x39)) (* digits *)
      then check_code u;
      match u with
      | x when x < 127 && x >= 0x20 ->
        Buffer.add_char s' (char_of_int x)
      | x when x<= 0xFFFF ->
        Buffer.add_string s' ("\\u" ^ hex4 x)
      | x ->
        Buffer.add_string s' ("\\U" ^ hex8 x)
  done;
  Buffer.contents s'
