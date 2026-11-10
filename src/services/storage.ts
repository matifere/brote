import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { config } from "../config.js";

let s3Client: S3Client | null = null;

export function getS3Client(): S3Client {
  if (!s3Client) {
    if (!config.awsEndpointUrlS3 || !config.awsAccessKeyId || !config.awsSecretAccessKey) {
      throw new Error("AWS S3 credentials or endpoint not set in environment.");
    }
    s3Client = new S3Client({
      region: config.awsRegion,
      endpoint: config.awsEndpointUrlS3,
      credentials: {
        accessKeyId: config.awsAccessKeyId,
        secretAccessKey: config.awsSecretAccessKey,
      },
      forcePathStyle: true,
    });
  }
  return s3Client;
}

export async function testStorage(): Promise<{
  success: boolean;
  bucket: string;
  testKey: string;
  uploadedContent: string;
  downloadedContent: string;
  objectsCount: number;
}> {
  const client = getS3Client();
  const bucket = config.storageBucket;
  const testKey = `e2e-test-${Date.now()}.txt`;
  const testContent = `Hello from Neon Object Storage! Generated at ${new Date().toISOString()}`;

  // 1. Upload object
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: testKey,
      Body: testContent,
      ContentType: "text/plain",
    })
  );

  // 2. Download object and verify
  const getRes = await client.send(
    new GetObjectCommand({
      Bucket: bucket,
      Key: testKey,
    })
  );
  const downloadedContent = (await getRes.Body?.transformToString()) || "";

  if (downloadedContent !== testContent) {
    throw new Error(
      `Content mismatch in Object Storage! Expected: "${testContent}", got: "${downloadedContent}"`
    );
  }

  // 3. List objects
  const listRes = await client.send(
    new ListObjectsV2Command({
      Bucket: bucket,
      MaxKeys: 10,
    })
  );
  const objectsCount = listRes.Contents?.length || 0;

  // 4. Clean up test object
  await client.send(
    new DeleteObjectCommand({
      Bucket: bucket,
      Key: testKey,
    })
  );

  return {
    success: true,
    bucket,
    testKey,
    uploadedContent: testContent,
    downloadedContent,
    objectsCount,
  };
}
