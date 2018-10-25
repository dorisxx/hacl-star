module Hacl.Impl.Frodo.KEM.Decaps

open FStar.HyperStack
open FStar.HyperStack.ST
open FStar.Mul

open LowStar.Buffer

open Lib.IntTypes
open Lib.Buffer

open Hacl.Impl.Matrix
open Hacl.Impl.Frodo.Params
open Hacl.Impl.Frodo.KEM
open Hacl.Impl.Frodo.KEM.Encaps
open Hacl.Impl.Frodo.Encode
open Hacl.Impl.Frodo.Pack
open Hacl.Impl.Frodo.Sample
open Hacl.Frodo.Random
open Hacl.Frodo.Clear

module ST = FStar.HyperStack.ST
module S = Spec.Frodo.KEM.Decaps
module M = Spec.Matrix
module LSeq = Lib.Sequence

#reset-options "--z3rlimit 100 --max_fuel 0 --max_ifuel 0 --using_facts_from '* -FStar.Seq'"

inline_for_extraction noextract
val get_bp_c_matrices:
     ct:lbytes crypto_ciphertextbytes
  -> bp_matrix:matrix_t params_nbar params_n
  -> c_matrix:matrix_t params_nbar params_nbar
  -> Stack unit
    (requires fun h ->
      live h ct /\ live h bp_matrix /\ live h c_matrix /\
      disjoint bp_matrix ct /\ disjoint c_matrix ct /\ disjoint bp_matrix c_matrix)
    (ensures  fun h0 _ h1 ->
      modifies (loc_union (loc_buffer bp_matrix) (loc_buffer c_matrix)) h0 h1 /\
      (as_matrix h1 bp_matrix, as_matrix h1 c_matrix) == S.get_bp_c_matrices (as_seq h0 ct))
let get_bp_c_matrices ct bp_matrix c_matrix =
  Spec.Frodo.KEM.expand_crypto_ciphertextbytes ();
  let c1Len = params_logq *! params_nbar *! params_n /. size 8 in
  let c2Len = params_logq *! params_nbar *! params_nbar /. size 8 in
  let c1 = sub #uint8 #_ #(v c1Len) ct (size 0) c1Len in
  let c2 = sub #uint8 #_ #(v c2Len) ct c1Len c2Len in
  frodo_unpack params_nbar params_n params_logq c1 bp_matrix;
  frodo_unpack params_nbar params_nbar params_logq c2 c_matrix

inline_for_extraction noextract
val get_bpp_cp_matrices:
     g:lbytes (size 3 *! crypto_bytes)
  -> mu_decode:lbytes bytes_mu
  -> sk:lbytes crypto_secretkeybytes
  -> bpp_matrix:matrix_t params_nbar params_n
  -> cp_matrix:matrix_t params_nbar params_nbar
  -> Stack unit
    (requires fun h ->
      live h g /\ live h mu_decode /\ live h sk /\
      live h bpp_matrix /\ live h cp_matrix /\
      disjoint g bpp_matrix /\ disjoint sk bpp_matrix /\
      disjoint mu_decode bpp_matrix /\ disjoint mu_decode cp_matrix /\
      disjoint g cp_matrix /\ disjoint sk cp_matrix /\ disjoint bpp_matrix cp_matrix)
    (ensures fun h0 _ h1 ->
      modifies (loc_union (loc_buffer bpp_matrix) (loc_buffer cp_matrix)) h0 h1 /\
      (as_matrix h1 bpp_matrix, as_matrix h1 cp_matrix) ==
      S.get_bpp_cp_matrices (as_seq h0 g) (as_seq h0 mu_decode) (as_seq h0 sk))
let get_bpp_cp_matrices g mu_decode sk bpp_matrix cp_matrix =
  assert (v params_nbar * v params_n % 2 = 0);
  push_frame();
  Spec.Frodo.KEM.expand_crypto_publickeybytes ();
  Spec.Frodo.KEM.expand_crypto_secretkeybytes ();
  let pk = sub #uint8 #_ #(v crypto_publickeybytes) sk crypto_bytes crypto_publickeybytes in
  let seed_a = sub #uint8 #_ #(v bytes_seed_a) pk (size 0) bytes_seed_a in
  let b = sub #uint8 #_ #(v ((params_logq *! params_n *! params_nbar) /. size 8)) pk bytes_seed_a (crypto_publickeybytes -! bytes_seed_a) in
  let seed_ep = sub #uint8 #_ #(v crypto_bytes) g (size 0) crypto_bytes in

  let sp_matrix  = matrix_create params_nbar params_n in
  frodo_sample_matrix params_nbar params_n crypto_bytes seed_ep (u16 4) sp_matrix;
  frodo_mul_add_sa_plus_e_main seed_a seed_ep sp_matrix bpp_matrix;

  frodo_mul_add_sb_plus_e_plus_mu b seed_ep mu_decode sp_matrix cp_matrix;
  clear_matrix sp_matrix;
  pop_frame()

inline_for_extraction noextract
val frodo_mu_decode:
    s_bytes:lbytes (size 2 *! params_n *! params_nbar)
  -> bp_matrix:matrix_t params_nbar params_n
  -> c_matrix:matrix_t params_nbar params_nbar
  -> mu_decode:lbytes bytes_mu
  -> Stack unit
    (requires fun h ->
      live h s_bytes /\ live h bp_matrix /\
      live h c_matrix /\ live h mu_decode /\
      disjoint mu_decode s_bytes)
    (ensures fun h0 _ h1 ->
      modifies (loc_buffer mu_decode) h0 h1 /\
      as_seq h1 mu_decode ==
      S.frodo_mu_decode (as_seq h0 s_bytes) (as_matrix h0 bp_matrix) (as_matrix h0 c_matrix))
let frodo_mu_decode s_bytes bp_matrix c_matrix mu_decode =
  push_frame();
  let s_matrix = matrix_create params_n params_nbar in
  let m_matrix = matrix_create params_nbar params_nbar in
  matrix_from_lbytes s_bytes s_matrix;
  matrix_mul_s bp_matrix s_matrix m_matrix;
  matrix_sub c_matrix m_matrix;
  frodo_key_decode params_extracted_bits m_matrix mu_decode;
  pop_frame()

inline_for_extraction noextract
val crypto_kem_dec_kp_s_cond:
    d:lbytes crypto_bytes
  -> dp:lbytes crypto_bytes
  -> bp_matrix:matrix_t params_nbar params_n
  -> bpp_matrix:matrix_t params_nbar params_n
  -> c_matrix:matrix_t params_nbar params_nbar
  -> cp_matrix:matrix_t params_nbar params_nbar
  -> Stack bool
    (requires fun h ->
      live h d /\ live h dp /\ live h bp_matrix /\
      live h bpp_matrix /\ live h c_matrix /\ live h cp_matrix)
    (ensures  fun h0 r h1 ->
      modifies loc_none h0 h1 /\
      r == S.crypto_kem_dec_kp_s_cond (as_seq h0 d) (as_seq h0 dp) (as_matrix h0 bp_matrix)
	(as_matrix h0 bpp_matrix) (as_matrix h0 c_matrix) (as_matrix h0 cp_matrix))
let crypto_kem_dec_kp_s_cond d dp bp_matrix bpp_matrix c_matrix cp_matrix =
  let b1 = Lib.ByteBuffer.lbytes_eq d dp in
  let b2 = matrix_eq params_logq bp_matrix bpp_matrix in
  let b3 = matrix_eq params_logq c_matrix cp_matrix in
  b1 && b2 && b3

inline_for_extraction noextract
val crypto_kem_dec_kp_s:
    mu_decode:lbytes bytes_mu
  -> g:lbytes (size 3 *! crypto_bytes)
  -> bp_matrix:matrix_t params_nbar params_n
  -> c_matrix:matrix_t params_nbar params_nbar
  -> sk:lbytes crypto_secretkeybytes
  -> ct:lbytes crypto_ciphertextbytes
  -> Stack bool
    (requires fun h ->
      live h mu_decode /\ live h bp_matrix /\ live h g /\
      live h c_matrix /\ live h sk /\ live h ct)
    (ensures fun h0 r h1 -> modifies loc_none h0 h1 /\
      r == S.crypto_kem_dec_kp_s (as_seq h0 mu_decode) (as_seq h0 g)
	(as_matrix h0 bp_matrix) (as_matrix h0 c_matrix) (as_seq h0 sk) (as_seq h0 ct))
let crypto_kem_dec_kp_s mu_decode g bp_matrix c_matrix sk ct =
  push_frame ();
  Spec.Frodo.KEM.expand_crypto_ciphertextbytes ();
  let dp = sub #uint8 #_ #(v crypto_bytes) g (crypto_bytes +! crypto_bytes) crypto_bytes in
  let d = sub #uint8 #_ #(v crypto_bytes) ct (crypto_ciphertextbytes -! crypto_bytes) crypto_bytes in

  let bpp_matrix = matrix_create params_nbar params_n in
  let cp_matrix  = matrix_create params_nbar params_nbar in
  get_bpp_cp_matrices g mu_decode sk bpp_matrix cp_matrix;
  let b = crypto_kem_dec_kp_s_cond d dp bp_matrix bpp_matrix c_matrix cp_matrix in
  pop_frame ();
  b

inline_for_extraction noextract
val crypto_kem_dec_ss0:
    ct:lbytes crypto_ciphertextbytes
  -> kp_s:lbytes crypto_bytes
  -> ss:lbytes crypto_bytes
  -> Stack unit
    (requires fun h ->
      live h ct /\ live h kp_s /\ live h ss /\
      disjoint ss ct /\ disjoint ss kp_s)
    (ensures fun h0 _ h1 -> modifies (loc_buffer ss) h0 h1 /\
      as_seq h1 ss == S.crypto_kem_dec_ss0 (as_seq h0 ct) (as_seq h0 kp_s))
let crypto_kem_dec_ss0 ct kp_s ss =
  push_frame();
  let c12 = sub ct (size 0) (crypto_ciphertextbytes -! crypto_bytes) in
  let d = sub #uint8 #_ #(v crypto_bytes) ct (crypto_ciphertextbytes -! crypto_bytes) crypto_bytes in

  let ss_init_len = crypto_ciphertextbytes +! crypto_bytes in
  let ss_init:lbytes ss_init_len = create ss_init_len (u8 0) in
  concat3 (crypto_ciphertextbytes -! crypto_bytes) c12 crypto_bytes kp_s crypto_bytes d ss_init;
  cshake_frodo ss_init_len ss_init (u16 7) crypto_bytes ss;
  pop_frame()

inline_for_extraction noextract
val crypto_kem_dec_ss:
    ct:lbytes crypto_ciphertextbytes
  -> sk:lbytes crypto_secretkeybytes
  -> g:lbytes (size 3 *! crypto_bytes)
  -> mu_decode:lbytes bytes_mu
  -> bp_matrix:matrix_t params_nbar params_n
  -> c_matrix:matrix_t params_nbar params_nbar
  -> ss:lbytes crypto_bytes
  -> Stack unit
    (requires fun h ->
      live h mu_decode /\ live h bp_matrix /\ live h g /\
      live h c_matrix /\ live h sk /\ live h ct /\ live h ss /\
      disjoint ss ct /\ disjoint ss sk /\ disjoint ss mu_decode /\
      disjoint ss bp_matrix /\ disjoint ss c_matrix /\ disjoint ss g)
    (ensures fun h0 _ h1 -> modifies (loc_buffer ss) h0 h1 /\
      as_seq h1 ss == S.crypto_kem_dec_ss (as_seq h0 ct) (as_seq h0 sk)
	(as_seq h0 g) (as_seq h0 mu_decode) (as_matrix h0 bp_matrix) (as_matrix h0 c_matrix))
let crypto_kem_dec_ss ct sk g mu_decode bp_matrix c_matrix ss =
  let b = crypto_kem_dec_kp_s mu_decode g bp_matrix c_matrix sk ct in
  let kp = sub #uint8 #_ #(v crypto_bytes) g crypto_bytes crypto_bytes in
  let s = sub #uint8 #_ #(v crypto_bytes) sk (size 0) crypto_bytes in
  let kp_s = if b then kp else s in
  crypto_kem_dec_ss0 ct kp_s ss

inline_for_extraction noextract
val crypto_kem_dec_0:
    mu_decode:lbytes bytes_mu
  -> sk:lbytes crypto_secretkeybytes
  -> g:lbytes (size 3 *! crypto_bytes)
  -> Stack unit
    (requires fun h ->
      live h mu_decode /\ live h sk /\ live h g /\
      disjoint mu_decode g /\ disjoint sk g)
    (ensures fun h0 _ h1 -> modifies (loc_buffer g) h0 h1 /\
     (let pk = LSeq.sub (as_seq h0 sk) (v crypto_bytes) (v crypto_publickeybytes) in
      let pk_mu_decode = LSeq.concat pk (as_seq h0 mu_decode) in
      as_seq h1 g == Spec.Frodo.Params.frodo_prf_spec (v crypto_publickeybytes + v bytes_mu)
	pk_mu_decode (u16 3) (3 * v crypto_bytes)))
let crypto_kem_dec_0 mu_decode sk g =
  let pk_mu_decode_len = crypto_publickeybytes +! bytes_mu in
  push_frame();
  let pk_mu_decode = create pk_mu_decode_len (u8 0) in
  let pk = sub #uint8 #_ #(v crypto_publickeybytes) sk crypto_bytes crypto_publickeybytes in
  concat2 crypto_publickeybytes pk bytes_mu mu_decode pk_mu_decode;
  cshake_frodo pk_mu_decode_len pk_mu_decode (u16 3) (size 3 *! crypto_bytes) g;
  pop_frame()

inline_for_extraction noextract
val crypto_kem_dec_1:
    mu_decode:lbytes bytes_mu
  -> bp_matrix:matrix_t params_nbar params_n
  -> c_matrix:matrix_t params_nbar params_nbar
  -> sk:lbytes crypto_secretkeybytes
  -> ct:lbytes crypto_ciphertextbytes
  -> ss:lbytes crypto_bytes
  -> Stack unit
    (requires fun h ->
      live h mu_decode /\ live h bp_matrix /\
      live h c_matrix /\ live h sk /\ live h ct /\ live h ss /\
      disjoint ss ct /\ disjoint ss sk /\ disjoint ss mu_decode /\
      disjoint ss bp_matrix /\ disjoint ss c_matrix)
    (ensures fun h0 _ h1 -> modifies (loc_buffer ss) h0 h1 /\
     (let pk = LSeq.sub (as_seq h0 sk) (v crypto_bytes) (v crypto_publickeybytes) in
      let pk_mu_decode = LSeq.concat pk (as_seq h0 mu_decode) in
      let g = Spec.Frodo.Params.frodo_prf_spec (v crypto_publickeybytes + v bytes_mu)
	pk_mu_decode (u16 3) (3 * v crypto_bytes) in
      as_seq h1 ss == S.crypto_kem_dec_ss (as_seq h0 ct) (as_seq h0 sk) g
	 (as_seq h0 mu_decode) (as_matrix h0 bp_matrix) (as_matrix h0 c_matrix)))
let crypto_kem_dec_1 mu_decode bp_matrix c_matrix sk ct ss =
  assert_spinoff (v (size 2 *! crypto_bytes) % 4 == 0);
  assert_spinoff (v (size 2 *! crypto_bytes) <= v (size 3 *! crypto_bytes));
  push_frame();
  let g = create (size 3 *! crypto_bytes) (u8 0) in
  crypto_kem_dec_0 mu_decode sk g;
  crypto_kem_dec_ss ct sk g mu_decode bp_matrix c_matrix ss;
  clear_words_u8 (size 2 *! crypto_bytes) g;
  pop_frame()

inline_for_extraction noextract
val crypto_kem_dec:
    ss:lbytes crypto_bytes
  -> ct:lbytes crypto_ciphertextbytes
  -> sk:lbytes crypto_secretkeybytes
  -> Stack uint32
    (requires fun h ->
      live h ss /\ live h ct /\ live h sk /\
      disjoint ss ct /\ disjoint ss sk /\ disjoint ct sk)
    (ensures  fun h0 _ h1 -> modifies (loc_buffer ss) h0 h1 /\
      as_seq h1 ss == S.crypto_kem_dec (as_seq h0 ct) (as_seq h0 sk))
let crypto_kem_dec ss ct sk =
  Spec.Frodo.KEM.expand_crypto_secretkeybytes ();
  push_frame();
  let bp_matrix = matrix_create params_nbar params_n in
  let c_matrix  = matrix_create params_nbar params_nbar in
  get_bp_c_matrices ct bp_matrix c_matrix;

  let s_bytes = sub sk (crypto_bytes +! crypto_publickeybytes) (size 2 *! params_n *! params_nbar) in
  let mu_decode = create bytes_mu (u8 0) in
  frodo_mu_decode s_bytes bp_matrix c_matrix mu_decode;
  crypto_kem_dec_1 mu_decode bp_matrix c_matrix sk ct ss;
  pop_frame();
  u32 0
