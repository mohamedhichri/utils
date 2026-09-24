#start a docker container in interactive shell
docker run --rm -it --user 0 --entrypoint /bin/bash YOUR_SPARK_IMAGE:TAG

#connect to a running openshift pod
oc exec -it -n hbtf-mlr EXECUTOR_POD_NAME -- /bin/bash

#check keystore content
"$JAVA_HOME/bin/keytool" -list -v \
  -keystore /etc/pki/java/cacerts \
  -storepass changeit

#check if s3 endpoint is using a certificate trusted by the CA
openssl s_client \
  -connect S3_HOST:443 \
  -servername S3_HOST \
  -verify_return_error \
  -CAfile /etc/pki/tls/certs/ca-bundle.crt \
  </dev/null
