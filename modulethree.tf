########################################################################################
#two instances with keypair, nginx installed on them, an elastic load balance
#attach to them,
#attaching tags to all resources created 
#create an s3 bucket
#send log of nginx to s3 bucket
#write a file to s3
########################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-east-1"
}
########################################################################################
#vpc
########################################################################################

resource "aws_vpc" "tayovpc" {
  cidr_block           = var.aws_vpc_cidr_block
  enable_dns_hostnames = "true"
  tags = {
    Name        = "devtayovpc"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#internet gateway
########################################################################################

resource "aws_internet_gateway" "tayoIGW" {
  vpc_id = aws_vpc.tayovpc.id
  tags = {
    Name        = "devtayoIGW"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#subnet
########################################################################################

resource "aws_subnet" "tayosubnet1" {
  vpc_id                  = aws_vpc.tayovpc.id
  cidr_block              = "${cidrsubnet(aws_vpc.tayovpc.cidr_block, 2, 1)}"
  map_public_ip_on_launch = "true"
  availability_zone       = var.availability_zone["zone1"]
  tags = {
    Name        = "devtayosubnet1"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#subnet
########################################################################################

resource "aws_subnet" "tayosubnet2" {
  vpc_id                  = aws_vpc.tayovpc.id
  cidr_block              = "${cidrsubnet(aws_vpc.tayovpc.cidr_block, 3, 1)}"
  map_public_ip_on_launch = "true"
  availability_zone       = var.availability_zone["zone2"]
  tags = {
    Name        = "devtayosubnet2"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#routetable
########################################################################################

resource "aws_route_table" "tayoRT" {
  vpc_id = aws_vpc.tayovpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tayoIGW.id
  }
  tags = {
    Name        = "devtayoRT"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#associating route table to subnet
########################################################################################

resource "aws_route_table_association" "tayoRTA1" {
  subnet_id      = aws_subnet.tayosubnet1.id
  route_table_id = aws_route_table.tayoRT.id

}

########################################################################################
#associating route table to subnet
########################################################################################

resource "aws_route_table_association" "tayoRTA2" {
  subnet_id      = aws_subnet.tayosubnet2.id
  route_table_id = aws_route_table.tayoRT.id

}

########################################################################################
#security group
########################################################################################

resource "aws_security_group" "tayosg" {
  name   = "tayoSG"
  vpc_id = aws_vpc.tayovpc.id

  #SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  #http access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #https access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "devtayosg"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#elastic loadbalancer
########################################################################################

resource "aws_elb" "web" {
  name = "nginx-elb"

  subnets         = ["${aws_subnet.tayosubnet1.id}", "${aws_subnet.tayosubnet2.id}"]
  security_groups = ["${aws_security_group.tayosg.id}"]
  instances       = ["${aws_instance.nginx1.id}", "${aws_instance.nginx2.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  tags = {
    Name        = "devweb"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#ec2 instance 1
########################################################################################

resource "aws_instance" "nginx1" {
  ami                    = "ami-c58c1dd3"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.tayosubnet1.id
  vpc_security_group_ids = ["${aws_security_group.tayosg.id}"]
  key_name               = "${var.key_name}"

  connection {
    user        = "ec2-user"
    host        = "${aws_instance.nginx1.public_ip}"
    private_key = "${file("monday.pem")}"
    timeout     = "3m"
  }

  #creating a file that contain access key for the s3config
  #so we send our log from nginx to s3
  provisioner "file" {
    content     = <<EOF
access_key = ${aws_iam_access_key.write_user.id}
secret_key = ${aws_iam_access_key.write_user.secret}
use_https = True
bucket_location = US

EOF
    destination = "/home/ec2-user/.s3cfg"

  }

  #creating a file to configure the log rotate process
  #add configurations like
  #how often to rotate the logs and other things
  #line 227 to get the instance ID and store it to the object
  #line 228 and 229 to upload the acccess and error log and send them to s3 bucket

  provisioner "file" {
    content     = <<EOF
/var/log/nginx/*log {
  daily
  rotate 10
  missingok
  compress
  sharedscripts
  postrotate
    INSTANCE_ID=`curl --silent http://169.254.169.254/latest/meta-data/instance-id`
    /usr/local/bin/s3cmd sync /var/log/nginx/access.log-* s3://${aws_s3_bucket.web_bucket.id}/$INSTANCE_ID/nginx/
    /usr/local/bin/s3cmd sync /var/log/nginx/error.log-* s3://${aws_s3_bucket.web_bucket.id}/$INSTANCE_ID/nginx/
  endscript
}   

EOF
    destination = "/home/ec2-user/nginx"

  }

  #install nginx
  #copy the two files created earlier to the appropraite loacation
  #install s3 cmd
  #run the command to copy the index.html and image from s3 to the files in the server
  #force rotate the log

  provisioner "remote-exec" {
    inline = [
      "sudo yum install nginx -y",
      "sudo service nginx start",
      "sudo cp /home/ec2-user/.s3cfg /root/.s3cfg",
      "sudo cp /home/ec2-user/nginx /etc/logrotate.d/nginx",
      "sudo pip install s3cmd",
      "s3cmd get s3://${aws_s3_bucket.web_bucket.id}/website/index.html .",
      "s3cmd get s3://${aws_s3_bucket.web_bucket.id}/website/Globo_logo_Vert.png .",
      "sudo cp /home/ec2-user/index.html /usr/share/nginx/html/index.html",
      "sudo cp /home/ec2-user/Globo_logo_Vert.png /usr/share/nginx/html/Globo_logo_Vert.png",
      "sudo logrotate -f /etc/logrotate.conf"
    ]
  }
  tags = {
    Name        = "devnginx1"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }

}

########################################################################################
#ec2 instance 2
########################################################################################

resource "aws_instance" "nginx2" {
  ami                    = "ami-c58c1dd3"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.tayosubnet2.id
  vpc_security_group_ids = ["${aws_security_group.tayosg.id}"]
  key_name               = "${var.key_name}"

  connection {
    user        = "ec2-user"
    host        = "${aws_instance.nginx2.public_ip}"
    private_key = "${file("monday.pem")}"
    timeout     = "3m"
  }

  #creating a file that contain access key for the s3config
  #so we send our log from nginx to s3
  provisioner "file" {
    content     = <<EOF
access_key = ${aws_iam_access_key.write_user.id}
secret_key = ${aws_iam_access_key.write_user.secret}
use_https = True
bucket_location = US

EOF
    destination = "/home/ec2-user/.s3cfg"

  }

  #creating a file to configure the log rotate process
  #add configurations like
  #how often to rotate the logs and other things
  #line 227 to get the instance ID and store it to the object
  #line 228 and 229 to upload the acccess and error log and send them to s3 bucket

  provisioner "file" {
    content     = <<EOF
/var/log/nginx/*log {
  daily
  rotate 10
  missingok
  compress
  sharedscripts
  postrotate
    INSTANCE_ID=`curl --silent http://169.254.169.254/latest/meta-data/instance-id`
    /usr/local/bin/s3cmd sync /var/log/nginx/access.log-* s3://${aws_s3_bucket.web_bucket.id}/$INSTANCE_ID/nginx/
    /usr/local/bin/s3cmd sync /var/log/nginx/error.log-* s3://${aws_s3_bucket.web_bucket.id}/$INSTANCE_ID/nginx/
  endscript
}   

EOF
    destination = "/home/ec2-user/nginx"

  }

  #install nginx
  #copy the two files created earlier to the appropraite loacation
  #install s3 cmd
  #run the command to copy the index.html and image from s3 to the files in the server
  #force rotate the log

  provisioner "remote-exec" {
    inline = [
      "sudo yum install nginx -y",
      "sudo service nginx start",
      "sudo cp /home/ec2-user/.s3cfg /root/.s3cfg",
      "sudo cp /home/ec2-user/nginx /etc/logrotate.d/nginx",
      "sudo pip install s3cmd",
      "s3cmd get s3://${aws_s3_bucket.web_bucket.id}/website/index.html .",
      "s3cmd get s3://${aws_s3_bucket.web_bucket.id}/website/Globo_logo_Vert.png .",
      "sudo cp /home/ec2-user/index.html /usr/share/nginx/html/index.html",
      "sudo cp /home/ec2-user/Globo_logo_Vert.png /usr/share/nginx/html/Globo_logo_Vert.png",
      "sudo logrotate -f /etc/logrotate.conf"
    ]
  }
  tags = {
    Name        = "devnginx2"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#s3 bucket confIGURATION
#creating an access key that will allow us to access s3
########################################################################################

########################################################################################
#creating an iam user
########################################################################################

resource "aws_iam_user" "write_user" {
  name          = "dev-s3-write-user"
  force_destroy = true
}

########################################################################################
#creating access key for the user
########################################################################################

resource "aws_iam_access_key" "write_user" {
  user = aws_iam_user.write_user.name
}

########################################################################################
#attaching policy, what permission this acccount should have
########################################################################################

resource "aws_iam_user_policy" "write_user_pol" {
  name   = "write"
  user   = aws_iam_user.write_user.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}",
        "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/*"
      ]
    }
  ]
}
EOF

}

########################################################################################
#creating the s3 bucket
#force destroy to destroy the bucket even if there is something in it
#policy yo grant access to proper user 
########################################################################################

resource "aws_s3_bucket" "web_bucket" {
  bucket        = "${var.environment_tag}-${var.bucket_name}"
  acl           = "private"
  force_destroy = true
  policy        = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "PublicReadForGetBucketObjects",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/*"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_user.write_user.arn}"
      },
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}",
        "arn:aws:s3:::${var.environment_tag}-${var.bucket_name}/*"
      ]
    }
  ]
}
EOF

  tags = {
    Name        = "devweb_bucket"
    BillingCode = var.billing_code_tag
    Environment = var.environment_tag
  }
}

########################################################################################
#uploadimng object into the s3 bucket
#key is the file path the content is to be copied to on s3
#source path of the file on your local
########################################################################################

resource "aws_s3_bucket_object" "website" {
  bucket = aws_s3_bucket.web_bucket.bucket
  key    = "/website/index.html"
  source = "index.html"

}

resource "aws_s3_bucket_object" "graphic" {
  bucket = aws_s3_bucket.web_bucket.bucket
  key    = "/website/Globo_logo_Vert.png"
  source = "Globo_logo_Vert.png"

}
#output the elb address
output "aws_elb_public_dns" {
  value = "${aws_elb.web.dns_name}"
}