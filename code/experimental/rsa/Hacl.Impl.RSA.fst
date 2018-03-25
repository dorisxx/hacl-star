module Hacl.Impl.RSA

open FStar.HyperStack.All
open FStar.Mul
open Spec.Lib.Loops
open Spec.Lib.IntBuf.Lemmas
open Spec.Lib.IntBuf
open Spec.Lib.IntTypes

open Hacl.Impl.Lib
open Hacl.Impl.MGF
open Hacl.Impl.Comparison
open Hacl.Impl.Convert
open Hacl.Impl.Exponentiation
open Hacl.Impl.Addition
open Hacl.Impl.Multiplication

module Buffer = Spec.Lib.IntBuf

inline_for_extraction let hLen:size_t = size 32

val xor_bytes:
    #len:size_nat ->
    clen:size_t{v clen == len} ->
    b1:lbytes len ->
    b2:lbytes len -> Stack unit
    (requires (fun h -> live h b1 /\ live h b2))
    (ensures (fun h0 _ h1 -> preserves_live h0 h1 /\ modifies1 b1 h0 h1))
    [@"c_inline"]
let xor_bytes #len clen b1 b2 = map2 #uint8 #uint8 #len clen (fun x y -> logxor #U8 x y) b1 b2
  
val pss_encode_:
    #sLen:size_nat -> #msgLen:size_nat -> #emLen:size_nat ->
    ssLen:size_t{v ssLen == sLen /\ sLen + v hLen + 8 < max_size_t} ->
    salt:lbytes sLen ->
    mmsgLen:size_t{v mmsgLen == msgLen} -> msg:lbytes msgLen ->
    eemLen:size_t{v eemLen == emLen /\  emLen - sLen - v hLen - 2 >= 0} ->
    em:lbytes emLen -> Stack unit
    (requires (fun h -> live h salt /\ live h msg /\ live h em /\ 
	              disjoint msg salt /\ disjoint em msg /\ disjoint em salt))
    (ensures (fun h0 _ h1 -> preserves_live h0 h1 /\ modifies1 em h0 h1))
    #reset-options "--z3rlimit 150 --max_fuel 0 --max_ifuel 0"
    [@"c_inline"]
let pss_encode_ #sLen #msgLen #emLen ssLen salt mmsgLen msg eemLen em =
    let m1_size:size_t = add #SIZE (add #SIZE (size 8) hLen) ssLen in
    assert_norm (v m1_size < max_size_t);
    let db_size:size_t = sub #SIZE (sub #SIZE eemLen hLen) (size 1) in
    
    assume (sLen + v hLen + 8 + 2 * emLen < max_size_t);
    assume (4 + 2 * v hLen + v hLen * v (blocks db_size hLen) < max_size_t);
    let stLen:size_t = add #SIZE (add #SIZE (add #SIZE (add #SIZE hLen m1_size) hLen) db_size) db_size in

    alloc #uint8 #unit #(v stLen) stLen (u8 0) [BufItem salt; BufItem msg] [BufItem em]
    (fun h0 _ h1 -> True)
    (fun st ->
       let mHash = Buffer.sub #uint8 #(v stLen) #(v hLen) st (size 0) hLen in
       let m1 = Buffer.sub #uint8 #(v stLen) #(v m1_size) st hLen m1_size in
       let m1Hash = Buffer.sub #uint8 #(v stLen) #(v hLen) st (add #SIZE hLen m1_size) hLen in
       let db = Buffer.sub #uint8 #(v stLen) #(v db_size) st (add #SIZE (add #SIZE hLen m1_size) hLen) db_size in
       let dbMask = Buffer.sub #uint8 #(v stLen) #(v db_size) st (add #SIZE (add #SIZE (add #SIZE hLen m1_size) hLen) db_size) db_size in
       disjoint_sub_lemma1 st msg (size 0) hLen;
       hash_sha256 mHash mmsgLen msg;
    
       let m1' = Buffer.sub #uint8 #(v m1_size) #(v hLen) m1 (size 8) hLen in
       copy hLen mHash m1';
       let m1' = Buffer.sub #uint8 #(v m1_size) #sLen m1 (add #SIZE (size 8) hLen) ssLen in
       copy ssLen salt m1';
       hash_sha256 m1Hash m1_size m1;
       
       let last_before_salt = sub #SIZE (sub #SIZE db_size ssLen) (size 1) in
       db.(last_before_salt) <- u8 1;
       let db' = Buffer.sub #uint8 #(v db_size) #sLen db (size_incr last_before_salt) ssLen in
       copy ssLen salt db';
    
       mgf_sha256 m1Hash db_size dbMask;
       xor_bytes db_size db dbMask;
       
       let em' = Buffer.sub #uint8 #emLen #(v db_size) em (size 0) db_size in
       copy db_size db em';
       let em' = Buffer.sub #uint8 #emLen #(v hLen) em db_size hLen in
       copy hLen m1Hash em';
       em.(size_decr eemLen) <- u8 0xbc
    )
		
val pss_encode:
    #sLen:size_nat -> #msgLen:size_nat -> #emLen:size_nat ->
    msBits:size_t{v msBits < 8} ->
    ssLen:size_t{v ssLen == sLen /\ sLen + v hLen + 8 < max_size_t} -> salt:lbytes sLen ->
    mmsgLen:size_t{v mmsgLen == msgLen /\ msgLen < pow2 61} -> msg:lbytes msgLen ->
    eemLen:size_t{v eemLen == emLen /\ emLen - sLen - v hLen - 3 >= 0} ->
    em:lbytes emLen -> Stack unit
    (requires (fun h -> live h salt /\ live h msg /\ live h em /\ disjoint msg salt /\ disjoint em msg /\ disjoint em salt))
    (ensures (fun h0 _ h1 -> preserves_live h0 h1 /\ modifies1 em h0 h1))
    #reset-options "--z3rlimit 50 --max_fuel 0"
    [@"c_inline"]
let pss_encode #sLen #msgLen #emLen msBits ssLen salt mmsgLen msg eemLen em =
    if (msBits =. size 0)
    then begin
	let em' = Buffer.sub #uint8 #emLen #(emLen - 1) em (size 1) (size_decr eemLen) in
	disjoint_sub_lemma1 em msg (size 1) (size_decr eemLen);
	disjoint_sub_lemma1 em salt (size 1) (size_decr eemLen);
	pss_encode_ ssLen salt mmsgLen msg (size_decr eemLen) em' end
    else begin
	pss_encode_ ssLen salt mmsgLen msg eemLen em;
	let shift' = sub #SIZE (size 8) msBits in
	em.(size 0) <- em.(size 0) &. (shift_right #U8 (u8 0xff) (size_to_uint32 shift'))
    end

val pss_verify_:
    #sLen:size_nat -> #msgLen:size_nat -> #emLen:size_nat ->
    ssLen:size_t{v ssLen == sLen /\ sLen + v hLen + 8 < max_size_t} ->
    msBits:size_t{v msBits < 8} ->
    eemLen:size_t{v eemLen == emLen /\ emLen - sLen - v hLen - 2 >= 0} ->
    em:lbytes emLen ->
    mmsgLen:size_t{v mmsgLen == msgLen} ->
    msg:lbytes msgLen -> Stack bool
    (requires (fun h -> live h em /\ live h msg /\ disjoint em msg))
    (ensures (fun h0 _ h1 -> preserves_live h0 h1 /\ modifies0 h0 h1))
    #reset-options "--z3rlimit 150 --max_fuel 0 --max_ifuel 0"
    [@"c_inline"]
let pss_verify_ #sLen #msgLen #emLen ssLen msBits eemLen em mmsgLen msg =
    let pad_size:size_t = sub #SIZE (sub #SIZE (sub #SIZE eemLen ssLen) hLen) (size 1) in
    let db_size:size_t = sub #SIZE (sub #SIZE eemLen hLen) (size 1) in
    assert_norm (v db_size < max_size_t);
    let m1_size:size_t = add #SIZE (add #SIZE (size 8) hLen) ssLen in
    assert_norm (v m1_size < max_size_t);
    
    assume (2 * emLen +  8 + v hLen  < max_size_t);
    assume (4 + 2 * v hLen + v hLen * v (blocks db_size hLen) < max_size_t);
    let stLen = add #SIZE (add #SIZE (add #SIZE (add #SIZE hLen pad_size) db_size) m1_size) hLen in
    
    alloc #uint8 #bool #(v stLen) stLen (u8 0) [BufItem em; BufItem msg] []
    (fun h0 _ h1 -> True)
    (fun st ->
       let mHash = Buffer.sub #uint8 #(v stLen) #(v hLen) st (size 0) hLen in
       let pad2 = Buffer.sub #uint8 #(v stLen) #(v pad_size) st hLen pad_size in
       let dbMask = Buffer.sub #uint8 #(v stLen) #(v db_size) st (add #SIZE hLen pad_size) db_size in
       let m1 = Buffer.sub #uint8 #(v stLen) #(v m1_size) st (add #SIZE (add #SIZE hLen pad_size) db_size) m1_size in
       let m1Hash' = Buffer.sub #uint8 #(v stLen) #(v hLen) st (add #SIZE (add #SIZE (add #SIZE hLen pad_size) db_size) m1_size) hLen in
       
       disjoint_sub_lemma1 st msg (size 0) hLen;
       hash_sha256 mHash mmsgLen msg;
       
       pad2.(size_decr pad_size) <- u8 0x01;
       let maskedDB = Buffer.sub #uint8 #emLen #(v db_size) em (size 0) db_size in
       let m1Hash = Buffer.sub #uint8 #emLen #(v hLen) em db_size hLen in
       mgf_sha256 m1Hash db_size dbMask;
       xor_bytes db_size dbMask maskedDB;
    
       (if (msBits >. size 0) then begin
	 let shift' = sub #SIZE (size 8) msBits in
	 dbMask.(size 0) <- dbMask.(size 0) &. (shift_right #U8 (u8 0xff) (size_to_uint32 shift')) end);

       //let pad = Buffer.sub #uint8 #stLen #(v pad_size) st (add #SIZE hLen pad_size) pad_size in
       let pad = Buffer.sub #uint8 #(v db_size) #(v pad_size) dbMask (size 0) pad_size in
       let salt = Buffer.sub #uint8 #(v db_size) #sLen dbMask pad_size ssLen in

       assume (disjoint pad pad2);
       let res =
	 if not (eq_b pad_size pad pad2) then false
	 else begin
	     let m1' = Buffer.sub #uint8 #(v m1_size) #(v hLen) m1 (size 8) hLen in
	     copy hLen mHash m1';
	     let m1' = Buffer.sub #uint8 #(v m1_size) #sLen m1 (add #SIZE (size 8) hLen) ssLen in
	     copy ssLen salt m1';
	     hash_sha256 m1Hash' m1_size m1;
	     disjoint_sub_lemma3 em st db_size hLen (add #SIZE (add #SIZE (add #SIZE hLen pad_size) db_size) m1_size) hLen;
	     eq_b hLen m1Hash m1Hash'
	end in
      res
    )

val pss_verify:
    #sLen:size_nat -> #msgLen:size_nat -> #emLen:size_nat ->
    ssLen:size_t{v ssLen == sLen /\ sLen + v hLen + 8 < max_size_t} ->
    msBits:size_t{v msBits < 8} ->
    eemLen:size_t{v eemLen == emLen /\ emLen - sLen - v hLen - 2 >= 0} ->
    em:lbytes emLen ->
    mmsgLen:size_t{v mmsgLen == msgLen} -> msg:lbytes msgLen -> Stack bool
    (requires (fun h -> live h em /\ live h msg /\ disjoint em msg))
    (ensures (fun h0 _ h1 -> preserves_live h0 h1 /\ modifies0 h0 h1))
    #reset-options "--z3rlimit 50 --max_fuel 0 --max_ifuel 0"
    [@"c_inline"]
let pss_verify #sLen #msgLen #emLen ssLen msBits eemLen em mmsgLen msg =
    let h0 = FStar.HyperStack.ST.get() in
    let em_0 = em.(size 0) &. (shift_left #U8 (u8 0xff) (size_to_uint32 msBits)) in
    let em_last = em.(size_decr eemLen) in

    let res = 
      if not ((eq_u8 em_0 (u8 0)) && (eq_u8 em_last (u8 0xbc)))
      then false
      else begin
	 let eemLen1 = if msBits =. size 0 then size_decr eemLen else eemLen in
	 let em1:lbytes (v eemLen1) =
	     if msBits =. size 0 then begin
	       let em' = Buffer.sub em (size 1) eemLen1 in
	       disjoint_sub_lemma1 em msg (size 1) eemLen1;
	       em' end
	     else em in
	 if (eemLen1 <. add #SIZE (add #SIZE ssLen hLen) (size 2)) then false
	 else pss_verify_ #sLen #msgLen #(v eemLen1) ssLen msBits eemLen1 em1 mmsgLen msg
      end in
    let h1 = FStar.HyperStack.ST.get() in
    assume (modifies0 h0 h1);
    res

val rsa_sign:
    #sLen:size_nat -> #msgLen:size_nat -> #nLen:size_nat ->
    pow2_i:size_t{6 * nLen + 4 * v pow2_i < max_size_t /\ nLen <= v pow2_i /\ nLen + 1 < 2 * v pow2_i} ->
    modBits:size_t{0 < v modBits /\ nLen = v (bits_to_bn modBits)} ->
    eBits:size_t{0 < v eBits /\ v eBits <= v modBits} ->
    dBits:size_t{0 < v dBits /\ v dBits <= v modBits} ->
    pLen:size_t -> qLen:size_t{nLen + v (bits_to_bn eBits) + v (bits_to_bn dBits) + v pLen + v qLen < max_size_t} ->
    skey:lbignum (nLen + v (bits_to_bn eBits) + v (bits_to_bn dBits) + v pLen + v qLen) ->
    rBlind:uint64 ->
    ssLen:size_t{v ssLen == sLen /\ sLen + v hLen + 8 < max_size_t /\ v (blocks modBits (size 8)) - sLen - v hLen - 3 >= 0} -> salt:lbytes sLen ->
    mmsgLen:size_t{v mmsgLen == msgLen /\ msgLen < pow2 61} -> msg:lbytes msgLen ->
    sgnt:lbytes (v (blocks modBits (size 8))) -> Stack unit
    (requires (fun h -> live h salt /\ live h msg /\ live h sgnt /\ live h skey /\
	              disjoint msg salt /\ disjoint msg sgnt /\ disjoint sgnt salt))
    (ensures (fun h0 _ h1 -> preserves_live h0 h1 /\ modifies1 sgnt h0 h1))

    #reset-options "--z3rlimit 1000 --max_fuel 0 --max_ifuel 0"
     
let rsa_sign #sLen #msgLen #nLen pow2_i modBits eBits dBits pLen qLen skey rBlind ssLen salt mmsgLen msg sgnt =
    let k = blocks modBits (size 8) in
    let msBits = (size_decr modBits) %. size 8 in

    //let nLen = bits_to_bn modBits in
    let nLen = get_size_nat k in
    let eLen = bits_to_bn eBits in
    let dLen = bits_to_bn dBits in
    let skeyLen:size_t = add #SIZE (add #SIZE (add #SIZE (add #SIZE nLen eLen) dLen) pLen) qLen in
    
    let n = Buffer.sub #uint64 #(v skeyLen) #(v nLen) skey (size 0) nLen in
    let e = Buffer.sub #uint64 #(v skeyLen) #(v eLen) skey nLen eLen in
    let d = Buffer.sub #uint64 #(v skeyLen) #(v dLen) skey (add #SIZE nLen eLen) dLen in
    let p = Buffer.sub #uint64 #(v skeyLen) #(v pLen) skey (add #SIZE (add #SIZE nLen eLen) dLen) pLen in
    let q = Buffer.sub #uint64 #(v skeyLen) #(v qLen) skey (add #SIZE ((add #SIZE (add #SIZE nLen eLen) dLen)) pLen) qLen in
    
    assume (2 * v nLen + 2 * (v pLen + v qLen) + 1 < max_size_t);   
    //assume (8 * v nLen < max_size_t);
    let n2Len = add #SIZE nLen nLen in
    let pqLen = add #SIZE pLen qLen in
    let stLen:size_t = add #SIZE n2Len (add #SIZE (add #SIZE pqLen pqLen) (size 1)) in
    
    alloc #uint8 #unit #(v k) k (u8 0) [BufItem skey; BufItem msg; BufItem salt] [BufItem sgnt]
    (fun h0 _ h1 -> True)
    (fun em -> 
       pss_encode msBits ssLen salt mmsgLen msg k em;
      	
       alloc #uint64 #unit #(v stLen) stLen (u64 0) [BufItem skey; BufItem em] [BufItem sgnt]
       (fun h0 _ h1 -> True)
       (fun tmp ->
           let m = Buffer.sub #uint64 #(v stLen) #(v nLen) tmp (size 0) nLen in
           let s = Buffer.sub #uint64 #(v stLen) #(v nLen) tmp nLen nLen in
           let phi_n = Buffer.sub #uint64 #(v stLen) #(v pqLen) tmp n2Len pqLen in
           let p1 = Buffer.sub #uint64 #(v stLen) #(v pLen) tmp (add #SIZE n2Len pqLen) pLen in
           let q1 = Buffer.sub #uint64 #(v stLen) #(v qLen) tmp (add #SIZE (add #SIZE n2Len pqLen) pLen) qLen in
           let dLen':size_t = add #SIZE (add #SIZE pLen qLen) (size 1) in
           let d' = Buffer.sub #uint64 #(v stLen) #(v dLen') tmp (add #SIZE n2Len pqLen) dLen' in admit();
           assume (disjoint m em);
           text_to_nat k em m;
           bn_sub_u64 pLen p (u64 1) p1; // p1 = p - 1
           bn_sub_u64 qLen q (u64 1) q1; // q1 = q - 1
           bn_mul pLen p1 qLen q1 phi_n; // phi_n = p1 * q1
           bn_mul_u64 pqLen phi_n rBlind d'; //d' = phi_n * rBlind
           assume (v dLen <= v dLen' /\ v dLen' * 64 < max_size_t);
           bn_add dLen' d' dLen d d'; //d' = d' + d
           assume (v nLen = v (bits_to_bn modBits));
           mod_exp pow2_i modBits nLen n m (mul #SIZE dLen' (size 64)) d' s;
           nat_to_text k s sgnt
        )
    )

val rsa_verify:
    #sLen:size_nat -> #msgLen:size_nat -> #nLen:size_nat ->
    pow2_i:size_t{6 * nLen + 4 * v pow2_i < max_size_t /\ nLen <= v pow2_i /\ nLen + 1 < 2 * v pow2_i} ->
    modBits:size_t{0 < v modBits /\ nLen = v (bits_to_bn modBits)} ->
    eBits:size_t{0 < v eBits /\ v eBits <= v modBits /\ nLen + v (bits_to_bn eBits) < max_size_t} ->
    pkey:lbignum (nLen + v (bits_to_bn eBits)) ->
    ssLen:size_t{v ssLen == sLen /\ sLen + v hLen + 8 < max_size_t /\ v (blocks modBits (size 8)) - sLen - v hLen - 3 >= 0} ->
    sgnt:lbytes (v (blocks modBits (size 8))) ->
    mmsgLen:size_t{v mmsgLen == msgLen /\ msgLen < pow2 61} -> msg:lbytes msgLen -> Stack bool
    (requires (fun h -> live h msg /\ live h sgnt /\ live h pkey /\ disjoint msg sgnt))
    (ensures (fun h0 _ h1 -> preserves_live h0 h1 /\ modifies0 h0 h1))

    #reset-options "--z3rlimit 750 --max_fuel 0 --max_ifuel 0"
    
let rsa_verify #sLen #msgLen #nLen pow2_i modBits eBits pkey ssLen sgnt mmsgLen msg =
    let k = blocks modBits (size 8) in
    let msBits = (size_decr modBits) %. size 8 in
    //let nLen = bits_to_bn modBits in
    let nLen = get_size_nat k in
    let eLen = bits_to_bn eBits in
    let pkeyLen:size_t = add #SIZE nLen eLen in

    let n = Buffer.sub #uint64 #(v pkeyLen) #(v nLen) pkey (size 0) nLen in
    let e = Buffer.sub #uint64 #(v pkeyLen) #(v eLen) pkey nLen eLen in

    let n2Len:size_t = add #SIZE nLen nLen in

    alloc #uint64 #bool #(v n2Len) n2Len (u64 0) [BufItem pkey; BufItem msg; BufItem sgnt] []
    (fun h0 _ h1 -> True)
    (fun tmp ->
        alloc #uint8 #bool #(v k) k (u8 0) [BufItem pkey; BufItem msg; BufItem sgnt] [BufItem tmp]
        (fun h0 _ h1 -> True)
	(fun em ->	
            let m = Buffer.sub #uint64 #(v n2Len) #(v nLen) tmp (size 0) nLen in
            let s = Buffer.sub #uint64 #(v n2Len) #(v nLen) tmp nLen nLen in
            disjoint_sub_lemma1 tmp sgnt nLen nLen;
            text_to_nat k sgnt s;
	    
            assume (disjoint s n);
	    let res = 
              if (bn_is_less nLen s nLen n) then begin
                 mod_exp pow2_i modBits nLen n s eBits e m;
                 disjoint_sub_lemma1 tmp em (size 0) nLen;
                 nat_to_text k m em;
                 pss_verify #sLen #msgLen #(v k) ssLen msBits k em mmsgLen msg end
              else false in admit();
            res
       )
    )
