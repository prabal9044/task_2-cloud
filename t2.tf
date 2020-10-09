provider "aws" {
	profile ="roger"
	region ="ap-south-1"
}


//Generating Key pair


resource "tls_private_key" "key-pair" {
algorithm = "RSA"
}


resource "aws_key_pair" "key" {
	depends_on = [ tls_private_key.key-pair ,]
	key_name = "task2-key"
	public_key = tls_private_key.key-pair.public_key_openssh

}



//security group
resource "aws_security_group" "efstask_sg" {
  name        = "efstask_sg"
  vpc_id      = "vpc-e7ebf68f"


  ingress {
    description = "PORT 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   
  ingress{
      description= "NFS"
       from_port= 2049
        to_port= 2049
        protocol="tcp"
        cidr_blocks = ["0.0.0.0/0"]
}


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "efstask_sg"
  }
}




// Launching The Instance
resource "aws_instance" "task2-os" {
    depends_on = [ aws_security_group.efstask_sg ,]
	ami           = "ami-0732b62d310b80e97"
	instance_type = "t2.micro"
	key_name = aws_key_pair.key.key_name
	security_groups = [ "efstask_sg" ]


	tags = {
		Name = "task2-os"
	}


// Connecting to the instance
	connection {
                
		type     = "ssh"
		user     = "ec2-user"
		private_key = tls_private_key.key-pair.private_key_pem
		host     = aws_instance.task2-os.public_ip
	}


// Installing the requirements
	provisioner "remote-exec" {
		inline = [
			"sudo yum install httpd  php git -y",
			"sudo systemctl restart httpd",
			"sudo systemctl enable httpd",
		]
	}


	

}

// Launching a EFS Storage
resource "aws_efs_file_system" "nfs-task2" {
            depends_on = [ aws_instance.task2-os,]
            creation_token = "nfs-task2"


	tags = {
		Name = "nfs-task2"
	}

}

// Mounting the EFS volume onto the VPCs Subnet


resource "aws_efs_mount_target" "target" {
	depends_on = [ aws_efs_file_system.nfs-task2 ,]
	file_system_id = aws_efs_file_system.nfs-task2.id
	subnet_id      = aws_instance.task2-os.subnet_id
	security_groups = ["${aws_security_group.efstask_sg.id}"]
}


output "myos-ip" {
	value = aws_instance.task2-os.public_ip
}




//Connect to instance again
resource "null_resource" "remote-connect"  {

        depends_on = [ aws_efs_mount_target.target ,]
        connection {
		type     = "ssh"
		user     = "ec2-user"
		private_key = tls_private_key.key-pair.private_key_pem
		host     = aws_instance.task2-os.public_ip
	}

// Mounting the EFS on the folder and pulling the code from github
 provisioner "remote-exec" {
      inline = [
        "sudo echo ${aws_efs_file_system.nfs-task2.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
        "sudo mount  ${aws_efs_file_system.nfs-task2.dns_name}:/  /var/www/html",
		"sudo git clone https://github.com/prabal9044/task_2-cloud.git /var/www/html/"
    ]
  }                            

}

//Creating S3 bucket
resource "aws_s3_bucket" "bucket" {
	bucket = "prabal9044"
	acl = "public-read"
    force_destroy = "true"  
    versioning {
		enabled = true
	}

}

//Downloading content from Github


resource "null_resource" "local-1"  {
	
	provisioner "local-exec" {
		command = "git clone https://github.com/prabal9044/task_2-cloud.git"
  	}

}



// Uploading file to bucket

resource "aws_s3_bucket_object" "file_upload" {
	bucket = aws_s3_bucket.bucket.id
         key = "rf.png"    
	source = "C:/Users/ASUS/Desktop/terraform_code/task2/ROGER.jpg"
        etag = filemd5("C:/Users/ASUS/Desktop/terraform_code/task2/ROGER.jpg")
	acl = "public-read"

}

// Creating Cloudfront Distribution


resource "aws_cloudfront_distribution" "distribution" {

	origin {
		domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
		origin_id   = "S3-prabal9044-id"


		custom_origin_config {
			http_port = 80
			https_port = 80
			origin_protocol_policy = "match-viewer"
			origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
		}
	}
 
	enabled = true
  
	default_cache_behavior {
		allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
		cached_methods = ["GET", "HEAD"]
		target_origin_id = "S3-prabal9044-id"
 
		forwarded_values {
			query_string = false
 
			cookies {
				forward = "none"
			}
		}
		viewer_protocol_policy = "allow-all"
		min_ttl = 0
		default_ttl = 3600
		max_ttl = 86400
	}
 
	restrictions {
		geo_restriction {
 
			restriction_type = "none"
		}
	}
 
	viewer_certificate {
		cloudfront_default_certificate = true
	}
}

output "domain-name" {
	value = aws_cloudfront_distribution.distribution.domain_name


}



