import ../../../lib/[Errors, Hash]
import ../../../Wallet/MinerWallet

import ../../../Database/Consensus/Elements/objects/VerificationObj

import ../SerializeCommon

proc parseVerification*(
  verifStr: string
): Verification {.forceCheck: [].} =
  #Holder's Nickname | Transaction Hash
  var verifSeq: seq[string] = verifStr.deserialize(
    NICKNAME_LEN,
    HASH_LEN
  )

  #Create the Verification.
  result = newVerificationObj(verifSeq[1].toHash[:256]())
  result.holder = uint16(verifSeq[0].fromBinary())

proc parseSignedVerification*(
  verifStr: string
): SignedVerification {.forceCheck: [
  ValueError
].} =
  #Holder's Nickname | Transaction Hash | BLS Signature
  var verifSeq: seq[string] = verifStr.deserialize(
    NICKNAME_LEN,
    HASH_LEN,
    BLS_SIGNATURE_LEN
  )

  #Create the Verification.
  try:
    result = newSignedVerificationObj(verifSeq[1].toHash[:256]())
    result.holder = uint16(verifSeq[0].fromBinary())
    result.signature = newBLSSignature(verifSeq[2])
  except BLSError:
    raise newLoggedException(ValueError, "Invalid signature.")
