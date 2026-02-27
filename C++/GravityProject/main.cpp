#include <iostream>
#include <cmath>
#include <vector>
#include <GLFW/glfw3.h>


//general settings
float SCREEN_WIDTH = 1200.0f;
float SCREEN_HEIGHT = 800.0f;
int BallNumSegments = 5;

//physics parameters
float G = 6.67430e-11f; // gravitational constant in m^3 kg^-1 s^-2
float deltaTime = 0.016f; // assuming ~60 FPS
float elasticity = 0.7f; // Coefficient of restitution for bounces


//initial object parameters
class Ball {
public:
    float x, y;
    float radius;
    double mass;
    float velocityX;
    float velocityY;
    
    // Constructor
	Ball(float startX, float startY, float r, double startMass = 5.97219 * pow(10, 24), float startVelX = 0.0f, float startVelY = 0.0f) //Default mass is Earth's mass
        : x(startX), y(startY), radius(r), mass(startMass), velocityX(startVelX), velocityY(startVelY) {
    }

    // Update function to handle bouncing
    void update() {
        // Update position based on velocity
        y += velocityY;

        // Check for collision with ground
        if (y - radius < 0.0f) {
            y = radius;              // Place ball on the ground
            velocityY = -velocityY * 0.8f;     // Bounce (reverse direction, lose energy)
        }

        // Check for collision with walls
        if (x - radius < 0.0f) {
            x = radius;              // Place ball at left wall
            velocityX = -velocityX * 0.8f;     // Bounce off left wall
        }
        else if (x + radius > SCREEN_WIDTH) {
            x = SCREEN_WIDTH - radius; // Place ball at right wall
            velocityX = -velocityX * 0.8f;     // Bounce off right wall
		}

		// Check for collision with ceiling
        if (y + radius > SCREEN_HEIGHT) {
            y = SCREEN_HEIGHT - radius; // Place ball at ceiling
            velocityY = -velocityY * 0.8f;     // Bounce off ceiling
		}

        // (Optional) add horizontal motion later using velocityX
        x += velocityX;
    }

    // Draw the ball
    void draw() {
        glBegin(GL_TRIANGLE_FAN);

        for (int i = 0; i <= BallNumSegments; i++) {
            double angle = i * 2.0 * 3.14159265358979323846 / BallNumSegments; // Calculate angle
            double drawx = x + (radius * cos(angle)); // Calculate x coordinate
            double drawy = y + (radius * sin(angle)); // Calculate y coordinate
            glVertex2d(drawx, drawy); // Vertex on circle perimeter
        }
        glEnd();
	}
};
std::vector<Ball> balls;
void CreateBall(float x = SCREEN_WIDTH / 2, float y = SCREEN_HEIGHT / 2, float radius = 50.0f) {
	Ball newBall = Ball(x, y, radius);
    balls.push_back(newBall);
}

void generateSolarSystem() {
    Ball sun = Ball(SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2, 20.0f, 1.989 * pow(10, 15)); // Sun-like mass
    balls.push_back(sun);
    Ball earth = Ball(SCREEN_WIDTH / 2 + 430.0f, SCREEN_HEIGHT / 2, 5.0f, 5.97219 * pow(10, 12), 0.0f, 2.0f); // Earth-like mass with initial tangential velocity
    balls.push_back(earth);
    Ball moon = Ball(SCREEN_WIDTH / 2 + 450.0f, SCREEN_HEIGHT / 2, 2.0f, 7.342 * pow(10, 7), 0.0f, 2.5f); // Moon-like mass with initial tangential velocity
    balls.push_back(moon);
};

void generateTwins() {
    Ball twin1 = Ball(SCREEN_WIDTH / 2 - 50.0f, SCREEN_HEIGHT / 2, 10.0f, 5.0f * pow(10, 15), 0.0f, -5.0f);
    balls.push_back(twin1);
    Ball twin2 = Ball(SCREEN_WIDTH / 2 + 50.0f, SCREEN_HEIGHT / 2, 10.0f, 5.0f * pow(10, 15), 0.0f, 5.0f);
    balls.push_back(twin2);
};

void generateIrregularTwins() {
    Ball twin1 = Ball(SCREEN_WIDTH / 2 - 100.0f, SCREEN_HEIGHT / 2, 10.0f, 5.0f * pow(10, 15), 0.0f, -2.0f);
    balls.push_back(twin1);
    Ball twin2 = Ball(SCREEN_WIDTH / 2 + 100.0f, SCREEN_HEIGHT / 2, 10.0f, 5.0f * pow(10, 15), 0.0f, 2.0f);
    balls.push_back(twin2);
};

void generate4SymmetricalBalls() {
    Ball ball1 = Ball(SCREEN_WIDTH / 2 - 150.0f, SCREEN_HEIGHT / 2, 10.0f, 6.0f * pow(10, 15), 0.0f, -6.0f);
    balls.push_back(ball1);
    Ball ball2 = Ball(SCREEN_WIDTH / 2 + 150.0f, SCREEN_HEIGHT / 2, 10.0f, 6.0f * pow(10, 15), 0.0f, 6.0f);
    balls.push_back(ball2);
    Ball ball3 = Ball(SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2 - 150.0f, 10.0f, 6.0f * pow(10, 15), 6.0f, 0.0f);
    balls.push_back(ball3);
    Ball ball4 = Ball(SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2 + 150.0f, 10.0f, 6.0f * pow(10, 15), -6.0f, 0.0f);
    balls.push_back(ball4);
};

void generateClusteredBalls() {
    for (int i = 0; i < 10; i++) {
        float x = SCREEN_WIDTH / 2 + (rand() % 100 - 50); // Random x around center
        float y = SCREEN_HEIGHT / 2 + (rand() % 100 - 50); // Random y around center
        Ball clusterBall = Ball(x, y, 5.0f, 1.0f * pow(10, 14), (rand() % 5) - 2, (rand() % 5) - 2); // Random small velocity
        balls.push_back(clusterBall);
    }
};

void generate3Body8Orbit() {
	double mass = 50.0f * pow(10, 13);
	float divisor = 4.3; //stable at 4 (slightly chaotic), 4.25 - 4.35 (rather stable)
    Ball left = Ball(SCREEN_WIDTH / 2 - 97.0f, SCREEN_HEIGHT / 2 + 24.3f, 10.0f, mass, 4.66f / divisor, 4.32f / divisor);
    balls.push_back(left);
    Ball center = Ball(SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2, 10.0f, mass, -9.32f / divisor, -8.65f / divisor);
    balls.push_back(center);
    Ball right = Ball(SCREEN_WIDTH / 2 + 97.0f, SCREEN_HEIGHT / 2 - 24.3f, 10.0f, mass, 4.66f / divisor, 4.32f / divisor);
    balls.push_back(right);
};

GLFWwindow* InitializeGLFW() {
    if (!glfwInit()) {
        std::cerr << "failed to initialize GLFW!" << std::endl;
        glfwTerminate();
        return nullptr; //returns nullptr because of the function return type
    }

    // Create a windowed mode window and its OpenGL context
    GLFWwindow* window = glfwCreateWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Gravity project", NULL, NULL);
    if (!window) {
        std::cerr << "Couldn't create window!" << std::endl;
        glfwTerminate();
        return nullptr; //returns nullptr because of the function return type
    }

    //window's context is now the current one, aka openGL commands affect this one
    glfwMakeContextCurrent(window);

    // Setup viewport and projection
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, SCREEN_WIDTH, 0, SCREEN_HEIGHT, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    return window;
}

int main(void) {
    GLFWwindow* window = InitializeGLFW();

    generateSolarSystem();

    while (!glfwWindowShouldClose(window)) {
		glClear(GL_COLOR_BUFFER_BIT); //render here

		// Update physics and draw balls
        for (auto& ball : balls) {
            ball.update();
			ball.draw();
        }

        //ball gravitational pull a = (G * m1 * m2) / d^2 * m1
        for (auto& b1 : balls) {
            for (auto& b2 : balls) {
                if (&b1 != &b2) {
					double accelX, accelY;
                    float dist = sqrt(pow(b1.x - b2.x,2) + pow(b1.y - b2.y,2));
                    if (dist > 0) { // Prevent division by zero
                        double force = (G * b1.mass * b2.mass) / (dist * dist); // Gravitational force magnitude
                        double accel = force / b1.mass; // Acceleration of b1 due to b2 (from F = m * a)
                        // Calculate direction from b1 to b2
                        double dirX = (b2.x - b1.x) / dist;
                        double dirY = (b2.y - b1.y) / dist;
                        // Calculate acceleration components
						accelX = dirX * accel; //can be negative based on direction vector
                        accelY = dirY * accel;
                        // Update velocities based on acceleration
                        b1.velocityX += accelX * deltaTime;
                        b1.velocityY += accelY * deltaTime;
                    }
                }
            }
        }

        //ball collision detection and response
        for (auto& b1 : balls) {
            for (auto& b2 : balls) {
                if (&b1 != &b2) {
                    if (sqrt(pow(b1.x - b2.x,2) + pow(b1.y - b2.y,2)) <= (b1.radius + b2.radius)) {
						std::cout << "Collision detected between balls!" << std::endl;
						// Simple elastic collision response
                        float nx = b2.x - b1.x; //normal x
						float ny = b2.y - b1.y; //normal y
						float dist = sqrt(nx * nx + ny * ny); //distance between balls
						nx /= dist; //normalize x
						ny /= dist; //normalize y

                        // Relative velocity
						float rvx = b2.velocityX - b1.velocityX; //relative velocity of ball 2 to ball 1 (x axis)
                        float rvy = b2.velocityY - b1.velocityY; //relative velocity of ball 2 to ball 1 (y axis)
						float velAlongNormal = rvx * nx + rvy * ny; //dot product (if negative, one of the vectors has an opposite component)

                        // Skip if separating
						if (velAlongNormal > 0) continue; //if positive, dot product indicates that vectors arent opposing each other, thus they are moving apart

                        // Compute impulse scalar
						float j = -(1 + elasticity) * velAlongNormal; //Impulse-momentum equation derived from Newton�s law of restitution
                        j /= (1 / b1.mass + 1 / b2.mass); //j is impulse magnitude

                        // Apply impulse
						b1.velocityX -= (j / b1.mass) * nx; //if j is negative, velocity will increase in opposite direction of normal vector
						b1.velocityY -= (j / b1.mass) * ny; //i know when to use += and -= here based on the direction of the normal vector
                        b2.velocityX += (j / b2.mass) * nx;
                        b2.velocityY += (j / b2.mass) * ny;

                    }
                }
            }
        }

        /* Swap front and back buffers */
        glfwSwapBuffers(window);
        /* Poll for and process events */
        glfwPollEvents();
    }

    //end
    std::cout << "Closing window..." << std::endl;
    glfwTerminate();
    std::cout << "Window closed successfully. No errors encountered" << std::endl;
    return 0;
}
