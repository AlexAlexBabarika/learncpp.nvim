#include <iostream>
#include <string_view>

class Animal
{
public:
    virtual ~Animal() = default;
    virtual std::string_view speak() const = 0;
};

class Dog : public Animal
{
public:
    std::string_view speak() const override { return "Woof"; }
    void fetch() const { std::cout << "fetching\n"; }
};

int main()
{
    Animal* pet{ new Dog{} };

    if (auto* dog{ dynamic_cast<Dog*>(pet) })
        dog->fetch();

    delete pet;
    return 0;
}
