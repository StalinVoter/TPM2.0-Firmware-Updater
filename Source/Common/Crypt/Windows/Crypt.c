/**
 * Windows CNG cryptography backend for Infineon TPMFactoryUpd 02.03.4733.00.
 */
#include "Crypt.h"
#include <bcrypt.h>
#include <Windows.h>

#pragma comment(lib, "bcrypt.lib")

#define CRC32MASKREV 0xEDB88320U

static unsigned int CalcHash(
    LPCWSTR algId,
    const BYTE* data,
    ULONG dataSize,
    BYTE* digest,
    ULONG digestSize)
{
    BCRYPT_ALG_HANDLE hAlg = NULL;
    BCRYPT_HASH_HANDLE hHash = NULL;
    PUCHAR object = NULL;
    DWORD objectSize = 0, cbResult = 0, hashSize = 0;
    NTSTATUS st;
    unsigned int rc = RC_E_FAIL;

    if (NULL == data || 0 == dataSize || NULL == digest || 0 == digestSize)
        return RC_E_BAD_PARAMETER;

    st = BCryptOpenAlgorithmProvider(&hAlg, algId, NULL, 0);
    if (st < 0) goto Cleanup;
    st = BCryptGetProperty(hAlg, BCRYPT_OBJECT_LENGTH, (PUCHAR)&objectSize, sizeof(objectSize), &cbResult, 0);
    if (st < 0) goto Cleanup;
    st = BCryptGetProperty(hAlg, BCRYPT_HASH_LENGTH, (PUCHAR)&hashSize, sizeof(hashSize), &cbResult, 0);
    if (st < 0 || hashSize != digestSize) goto Cleanup;

    object = (PUCHAR)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, objectSize);
    if (NULL == object) goto Cleanup;
    st = BCryptCreateHash(hAlg, &hHash, object, objectSize, NULL, 0, 0);
    if (st < 0) goto Cleanup;
    st = BCryptHashData(hHash, (PUCHAR)data, dataSize, 0);
    if (st < 0) goto Cleanup;
    st = BCryptFinishHash(hHash, digest, digestSize, 0);
    if (st < 0) goto Cleanup;
    rc = RC_SUCCESS;

Cleanup:
    if (hHash) BCryptDestroyHash(hHash);
    if (object) HeapFree(GetProcessHeap(), 0, object);
    if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
    if (RC_SUCCESS != rc && digest) SecureZeroMemory(digest, digestSize);
    return rc;
}

_Check_return_
unsigned int Crypt_HMAC(
    _In_bytecount_(PusInputMessageSize) const BYTE* PrgbInputMessage,
    _In_ UINT16 PusInputMessageSize,
    _In_opt_bytecount_(TSS_SHA1_DIGEST_SIZE) const BYTE PrgbKey[TSS_SHA1_DIGEST_SIZE],
    _Out_bytecap_(TSS_SHA1_DIGEST_SIZE) BYTE PrgbHMAC[TSS_SHA1_DIGEST_SIZE])
{
    BCRYPT_ALG_HANDLE hAlg = NULL;
    BCRYPT_HASH_HANDLE hHash = NULL;
    PUCHAR object = NULL;
    BYTE zeroKey[TSS_SHA1_DIGEST_SIZE] = {0};
    const BYTE* key = PrgbKey ? PrgbKey : zeroKey;
    DWORD objectSize = 0, cbResult = 0, hashSize = 0;
    NTSTATUS st;
    unsigned int rc = RC_E_FAIL;

    if (NULL == PrgbInputMessage || 0 == PusInputMessageSize || NULL == PrgbHMAC)
        return RC_E_BAD_PARAMETER;

    st = BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_SHA1_ALGORITHM, NULL, BCRYPT_ALG_HANDLE_HMAC_FLAG);
    if (st < 0) goto Cleanup;
    st = BCryptGetProperty(hAlg, BCRYPT_OBJECT_LENGTH, (PUCHAR)&objectSize, sizeof(objectSize), &cbResult, 0);
    if (st < 0) goto Cleanup;
    st = BCryptGetProperty(hAlg, BCRYPT_HASH_LENGTH, (PUCHAR)&hashSize, sizeof(hashSize), &cbResult, 0);
    if (st < 0 || TSS_SHA1_DIGEST_SIZE != hashSize) goto Cleanup;
    object = (PUCHAR)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, objectSize);
    if (!object) goto Cleanup;
    st = BCryptCreateHash(hAlg, &hHash, object, objectSize, (PUCHAR)key, TSS_SHA1_DIGEST_SIZE, 0);
    if (st < 0) goto Cleanup;
    st = BCryptHashData(hHash, (PUCHAR)PrgbInputMessage, PusInputMessageSize, 0);
    if (st < 0) goto Cleanup;
    st = BCryptFinishHash(hHash, PrgbHMAC, TSS_SHA1_DIGEST_SIZE, 0);
    if (st < 0) goto Cleanup;
    rc = RC_SUCCESS;

Cleanup:
    if (hHash) BCryptDestroyHash(hHash);
    if (object) HeapFree(GetProcessHeap(), 0, object);
    if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
    if (RC_SUCCESS != rc && PrgbHMAC) SecureZeroMemory(PrgbHMAC, TSS_SHA1_DIGEST_SIZE);
    return rc;
}

_Check_return_
unsigned int Crypt_SHA1(const BYTE* p, const UINT16 n, BYTE out[TSS_SHA1_DIGEST_SIZE])
{ return CalcHash(BCRYPT_SHA1_ALGORITHM, p, n, out, TSS_SHA1_DIGEST_SIZE); }

_Check_return_
unsigned int Crypt_SHA256(const BYTE* p, const UINT32 n, BYTE out[TSS_SHA256_DIGEST_SIZE])
{ return CalcHash(BCRYPT_SHA256_ALGORITHM, p, n, out, TSS_SHA256_DIGEST_SIZE); }

_Check_return_
unsigned int Crypt_SHA384(const BYTE* p, const UINT32 n, BYTE out[TSS_SHA384_DIGEST_SIZE])
{ return CalcHash(BCRYPT_SHA384_ALGORITHM, p, n, out, TSS_SHA384_DIGEST_SIZE); }

_Check_return_
unsigned int Crypt_SHA512(const BYTE* p, const UINT32 n, BYTE out[TSS_SHA512_DIGEST_SIZE])
{ return CalcHash(BCRYPT_SHA512_ALGORITHM, p, n, out, TSS_SHA512_DIGEST_SIZE); }

_Check_return_
unsigned int Crypt_SeedRandom(const BYTE* PrgbSeed, const UINT16 PusSeedSize)
{
    /* BCryptGenRandom uses the Windows system CSPRNG and does not accept an external seed. */
    if (NULL == PrgbSeed && 0 != PusSeedSize)
        return RC_E_BAD_PARAMETER;
    return RC_SUCCESS;
}

_Check_return_
unsigned int Crypt_GetRandom(const UINT16 PusRandomSize, BYTE* PrgbRandom)
{
    if (NULL == PrgbRandom || 0 == PusRandomSize)
        return RC_E_BAD_PARAMETER;
    return (BCryptGenRandom(NULL, PrgbRandom, PusRandomSize, BCRYPT_USE_SYSTEM_PREFERRED_RNG) >= 0)
        ? RC_SUCCESS : RC_E_FAIL;
}

static unsigned int ImportRsaPublicKey(
    const BYTE* modulus, UINT32 modulusSize,
    const BYTE* exponent, UINT32 exponentSize,
    BCRYPT_ALG_HANDLE* phAlg, BCRYPT_KEY_HANDLE* phKey)
{
    BCRYPT_RSAKEY_BLOB* hdr;
    PUCHAR blob = NULL;
    ULONG blobSize;
    NTSTATUS st;

    if (!modulus || !modulusSize || !exponent || !exponentSize || !phAlg || !phKey)
        return RC_E_BAD_PARAMETER;

    *phAlg = NULL;
    *phKey = NULL;
    st = BCryptOpenAlgorithmProvider(phAlg, BCRYPT_RSA_ALGORITHM, NULL, 0);
    if (st < 0) return RC_E_FAIL;

    blobSize = (ULONG)(sizeof(BCRYPT_RSAKEY_BLOB) + exponentSize + modulusSize);
    blob = (PUCHAR)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, blobSize);
    if (!blob)
    {
        BCryptCloseAlgorithmProvider(*phAlg, 0);
        *phAlg = NULL;
        return RC_E_FAIL;
    }

    hdr = (BCRYPT_RSAKEY_BLOB*)blob;
    hdr->Magic = BCRYPT_RSAPUBLIC_MAGIC;
    hdr->BitLength = modulusSize * 8U;
    hdr->cbPublicExp = exponentSize;
    hdr->cbModulus = modulusSize;
    hdr->cbPrime1 = 0;
    hdr->cbPrime2 = 0;
    CopyMemory(blob + sizeof(*hdr), exponent, exponentSize);
    CopyMemory(blob + sizeof(*hdr) + exponentSize, modulus, modulusSize);

    st = BCryptImportKeyPair(*phAlg, NULL, BCRYPT_RSAPUBLIC_BLOB, phKey, blob, blobSize, 0);
    SecureZeroMemory(blob, blobSize);
    HeapFree(GetProcessHeap(), 0, blob);
    if (st < 0)
    {
        BCryptCloseAlgorithmProvider(*phAlg, 0);
        *phAlg = NULL;
        return RC_E_FAIL;
    }
    return RC_SUCCESS;
}

_Check_return_
unsigned int Crypt_EncryptRSA(
    _In_ CRYPT_ENC_SCHEME PusEncryptionScheme,
    _In_ UINT32 PunInputDataSize,
    _In_bytecount_(PunInputDataSize) const BYTE* PrgbInputData,
    _In_ UINT32 PunPublicModulusSize,
    _In_bytecount_(PunPublicModulusSize) const BYTE* PrgbPublicModulus,
    _In_ UINT32 PunPublicExponentSize,
    _In_bytecount_(PunPublicExponentSize) const BYTE* PrgbPublicExponent,
    _In_ UINT32 PunLabelSize,
    _In_bytecount_(PunLabelSize) const BYTE* PrgbLabel,
    _Inout_ unsigned int* PpunEncryptedDataSize,
    _Inout_bytecap_(*PpunEncryptedDataSize) BYTE* PrgbEncryptedData)
{
    BCRYPT_ALG_HANDLE hAlg = NULL;
    BCRYPT_KEY_HANDLE hKey = NULL;
    BCRYPT_OAEP_PADDING_INFO pad;
    ULONG required = 0, written = 0;
    NTSTATUS st;
    unsigned int rc;

    if (!PrgbInputData || !PunInputDataSize || !PrgbPublicModulus || !PunPublicModulusSize ||
        !PrgbPublicExponent || !PunPublicExponentSize || !PrgbLabel || !PunLabelSize ||
        !PpunEncryptedDataSize || !PrgbEncryptedData)
        return RC_E_BAD_PARAMETER;
    if (CRYPT_ES_RSAESOAEP_SHA1_MGF1 != PusEncryptionScheme)
        return RC_E_INTERNAL;
    if (*PpunEncryptedDataSize < PunPublicModulusSize)
        return RC_E_BUFFER_TOO_SMALL;

    rc = ImportRsaPublicKey(PrgbPublicModulus, PunPublicModulusSize,
                            PrgbPublicExponent, PunPublicExponentSize, &hAlg, &hKey);
    if (RC_SUCCESS != rc) return rc;

    ZeroMemory(&pad, sizeof(pad));
    pad.pszAlgId = BCRYPT_SHA1_ALGORITHM;
    pad.pbLabel = (PUCHAR)PrgbLabel;
    pad.cbLabel = PunLabelSize;

    st = BCryptEncrypt(hKey, (PUCHAR)PrgbInputData, PunInputDataSize, &pad,
                       NULL, 0, NULL, 0, &required, BCRYPT_PAD_OAEP);
    if (st < 0 || required > *PpunEncryptedDataSize)
    {
        rc = (required > *PpunEncryptedDataSize) ? RC_E_BUFFER_TOO_SMALL : RC_E_FAIL;
        goto Cleanup;
    }
    st = BCryptEncrypt(hKey, (PUCHAR)PrgbInputData, PunInputDataSize, &pad,
                       NULL, 0, PrgbEncryptedData, *PpunEncryptedDataSize, &written, BCRYPT_PAD_OAEP);
    if (st < 0) { rc = RC_E_FAIL; goto Cleanup; }
    *PpunEncryptedDataSize = written;
    rc = RC_SUCCESS;

Cleanup:
    if (hKey) BCryptDestroyKey(hKey);
    if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
    return rc;
}

_Check_return_
unsigned int Crypt_VerifySignature(
    _In_bytecount_(PunMessageHashSize) const BYTE* PrgbMessageHash,
    _In_ const UINT32 PunMessageHashSize,
    _In_bytecount_(PunSignatureSize) const BYTE* PrgbSignature,
    _In_ const UINT32 PunSignatureSize,
    _In_bytecount_(PunModulusSize) const BYTE* PrgbModulus,
    _In_ const UINT32 PunModulusSize)
{
    BCRYPT_ALG_HANDLE hAlg = NULL;
    BCRYPT_KEY_HANDLE hKey = NULL;
    BCRYPT_PSS_PADDING_INFO pad;
    NTSTATUS st;
    unsigned int rc;

    if (!PrgbMessageHash || !PunMessageHashSize || !PrgbSignature || !PunSignatureSize ||
        !PrgbModulus || RSA2048_MODULUS_SIZE != PunModulusSize)
        return RC_E_BAD_PARAMETER;

    rc = ImportRsaPublicKey(PrgbModulus, PunModulusSize,
                            RSA_DEFAULT_PUB_EXPONENT, (UINT32)sizeof(RSA_DEFAULT_PUB_EXPONENT),
                            &hAlg, &hKey);
    if (RC_SUCCESS != rc) return rc;

    pad.pszAlgId = BCRYPT_SHA256_ALGORITHM;
    pad.cbSalt = CRYPT_PSS_PADDING_SALT_SIZE;
    st = BCryptVerifySignature(hKey, &pad, (PUCHAR)PrgbMessageHash, PunMessageHashSize,
                               (PUCHAR)PrgbSignature, PunSignatureSize, BCRYPT_PAD_PSS);
    if (0 == st)
        rc = RC_SUCCESS;
    else if ((NTSTATUS)0xC000A000L == st) /* STATUS_INVALID_SIGNATURE */
        rc = RC_E_VERIFY_SIGNATURE;
    else
        rc = RC_E_VERIFY_SIGNATURE;

    if (hKey) BCryptDestroyKey(hKey);
    if (hAlg) BCryptCloseAlgorithmProvider(hAlg, 0);
    return rc;
}

_Check_return_
unsigned int Crypt_CRC(const void* PpInputData, int PnInputDataSize, unsigned int* PpunCRC)
{
    unsigned int unCRC;
    const unsigned char* pbInputData;
    int nIndex;

    if (NULL == PpunCRC || NULL == PpInputData || 0 == PnInputDataSize)
        return RC_E_BAD_PARAMETER;

    unCRC = ~(*PpunCRC);
    pbInputData = (const unsigned char*)PpInputData;
    while (PnInputDataSize-- != 0)
    {
        unCRC ^= *pbInputData++;
        for (nIndex = 0; nIndex < 8; nIndex++)
            unCRC = (unCRC >> 1) ^ (-((int)(unCRC & 1U)) & CRC32MASKREV);
    }
    *PpunCRC = ~unCRC;
    return RC_SUCCESS;
}
