import os
import base64
import hashlib
import boto3

REGION = os.getenv("AWS_REGION", "ap-northeast-2")
KMS_KEY_ID = os.getenv("COLUMN_KMS_KEY_ID", "alias/finpay-dev-main")

kms = boto3.client("kms", region_name=REGION)


def normalize_email(email: str) -> str:
    return email.strip().lower()


def hash_email(email: str) -> str:
    if not email:
        return ""
    return hashlib.sha256(normalize_email(email).encode("utf-8")).hexdigest()


def encrypt_email(email: str) -> str:
    if not email:
        return ""

    response = kms.encrypt(
        KeyId=KMS_KEY_ID,
        Plaintext=email.encode("utf-8"),
        EncryptionContext={
            "purpose": "column-encryption",
            "table": "merchant_assignments",
            "column": "email",
        },
    )

    return base64.b64encode(response["CiphertextBlob"]).decode("utf-8")


def decrypt_email(ciphertext_b64: str) -> str:
    if not ciphertext_b64:
        return ""

    response = kms.decrypt(
        CiphertextBlob=base64.b64decode(ciphertext_b64),
        EncryptionContext={
            "purpose": "column-encryption",
            "table": "merchant_assignments",
            "column": "email",
        },
    )

    return response["Plaintext"].decode("utf-8")