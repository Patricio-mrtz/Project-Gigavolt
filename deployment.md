# Deployment and Reproduction

## AWS prerequisites

- Ubuntu EC2 instance
- `LabInstanceProfile` or equivalent IAM role with permission to read the required S3 objects
- Internet access for package repositories, Ollama, Hugging Face model files, and course datasets

## Required S3 objects

- `s3://projectmilestone1bucket/bucket.txt`
- `s3://projectmilestone3/Project milestone 3.txt`
- `s3://milestone4.1/new 2.txt`

Copies of the scripts represented by these S3 objects are included under `aws_dependencies/`.

## Deploy

1. Create a fresh Ubuntu EC2 instance with the required IAM role.
2. Paste `user_data/milestone6_user_data.sh` into EC2 User Data.
3. Launch the instance and monitor `/var/log/final-milestone.log`.
4. Confirm the final message `MILESTONE 6 READY`.
5. Connect to the instance and run:

```bash
cd /home/ubuntu/milestone5
source /opt/vector_env/bin/activate
python final/orchestrator.py
python rag_pipeline.py
python rag_pipeline.py --benchmark 1
```

## Verify services

```bash
systemctl is-active mariadb
systemctl is-active mongod
systemctl is-active ollama
```
