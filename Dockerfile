# Start from an official Maven image to build the app
FROM maven:3.6.3-jdk-8 AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy the pom.xml and source code
COPY pom.xml .
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests

# Start a new stage for the final image
FROM openjdk:8-jre-alpine

# Set the working directory inside the container
WORKDIR /app

# Copy the JAR file from the Maven build stage
COPY --from=builder /app/target/*.jar /app/application.jar

# Expose the application port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "/app/application.jar"]
