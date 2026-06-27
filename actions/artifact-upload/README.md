# `artifact-upload` action

Uploads a file to **GitHub Artifacts** and/or **S3 / MinIO** (any S3-compatible
store), returning a presigned download URL for the S3 copy. Handy for shipping a
build (APK/AAB/IPA) or a screenshots zip somewhere you can grab later.

## Requirements (read me first)

| What you need | Details |
|---|---|
| **Runner** | Any (Linux or macOS). The AWS CLI is auto-installed if `to-s3: true` and it's missing. **S3 mode also needs Dart on `PATH`** (it runs a small Dart CLI to presign + upload) — a prior Flutter/Dart setup provides it; GitHub-Artifacts-only mode does not. |
| **Run before this** | The file must exist (e.g. a build step's output path). |
| **Secrets / credentials (only for S3)** | Standard AWS env vars on the step: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` (or `AWS_DEFAULT_REGION`). For MinIO/self-hosted, also set `s3-endpoint`. GitHub-Artifacts mode needs **no** credentials. |

## Usage (GitHub Artifacts)

```yaml
- uses: vymalo/flutter-tools/actions/artifact-upload@v0
  with:
    file: ${{ steps.build.outputs.aab-path }}
    to-gh-artifacts: 'true'
```

## Usage (S3 / MinIO, with presigned URL)

```yaml
- id: up
  uses: vymalo/flutter-tools/actions/artifact-upload@v0
  env:
    AWS_ACCESS_KEY_ID:     ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    AWS_REGION: us-east-1
  with:
    file: build/app.aab
    to-gh-artifacts: 'false'
    to-s3: 'true'
    s3-bucket: my-builds
    s3-key: app/${{ github.run_id }}/app.aab
    s3-endpoint: https://minio.example.com   # omit for real AWS S3
- run: echo "Download: ${{ steps.up.outputs.s3-url }}"
```

## Inputs (most-used)

| Input | Required | Default | What it does |
|---|---|---|---|
| `file` | **yes** | — | Path to the artifact (workspace-relative or absolute). |
| `to-gh-artifacts` | no | `true` | Upload to GitHub Artifacts. |
| `to-s3` | no | `false` | Also upload to S3/MinIO. |
| `s3-bucket` + `s3-key` | for S3 | — | Destination bucket + object key. |
| `s3-endpoint` | for MinIO | — | S3-compatible endpoint. Empty = real AWS S3. |
| `s3-make-bucket` | no | `true` | Create the bucket if it's missing. **Set `false` to fail loud** instead of auto-creating an orphan bucket on a mistyped `s3-bucket`. |
| `s3-expires-in` | no | `604800` | Presigned-URL lifetime (seconds; default 7 days). |

## Outputs

| Output | What |
|---|---|
| `s3-url` | Presigned download URL (empty when `to-s3` is false). |
| `s3-key` | The object key written. |
